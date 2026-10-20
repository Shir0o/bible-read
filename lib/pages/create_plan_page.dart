import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_plan_config.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../models/schedule_mode.dart';
import '../services/group_service.dart';
import '../services/plan_completion_coordinator.dart';
import '../services/plan_generator.dart';
import '../services/reading_plan_service.dart';
import '../services/reference_parser.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import '../widgets/animated_action_button.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/common_styles.dart';
import '../widgets/start_chapter_sheet.dart';
import '../widgets/sub_header.dart';
import '../services/nudge_service.dart';
import 'group_members_page.dart';
import 'plan_detail_page.dart';

/// Who a new plan is for. Answered as a field inside the creation flow
/// (#809), not as a fork before it begins.
enum PlanAudience { solo, group }

enum _PlanGoalMethod { endDate, versesPerDay, chaptersPerDay }

class CreatePlanPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  /// When set, the page edits this existing plan in place instead of creating a
  /// new one: the form pre-fills from the plan's saved configuration and the
  /// CTA becomes "Save changes". Requires [editingProgress] for the start date.
  final ReadingPlan? editingPlan;

  /// The progress record for [editingPlan], used to anchor the schedule to the
  /// plan's original start date so editing doesn't shift existing days.
  final UserPlanProgress? editingProgress;

  /// Service used when the reader chooses to read with a group: the same flow
  /// creates the Group and its shared plan together. Optional so existing
  /// callers and tests that never touch the group branch keep working.
  final GroupService? groupService;

  /// Which audience the form opens on. "Create a group" entry points open it
  /// on [PlanAudience.group].
  final PlanAudience initialAudience;

  const CreatePlanPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.vibrationService = const VibrationService(),
    this.editingPlan,
    this.editingProgress,
    this.groupService,
    this.initialAudience = PlanAudience.solo,
  });

  @override
  State<CreatePlanPage> createState() => _CreatePlanPageState();
}

class _CreatePlanPageState extends State<CreatePlanPage> {
  final _titleController = TextEditingController();
  PlanType _selectedType = PlanType.sequential;
  int _years = 1;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  final Set<int> _readingDays = {
    1,
    2,
    3,
    4,
    5,
    6,
  }; // 1 = Mon, 6 = Sat (no Sun default)
  final Set<String> _selectedBooks = Set.from(ReferenceParser.allBooks);
  int? _customChaptersPerDay;
  int? _customVersesPerDay;
  _PlanGoalMethod _goalMethod = _PlanGoalMethod.endDate;
  late PlanAudience _audience = widget.initialAudience;
  final TextEditingController _groupNameController = TextEditingController();
  bool _isCreating = false;
  bool _isCustomPlanExpanded = false;

  /// The reader's Starting point (ADR-0005): "I've already read up to this
  /// chapter" when migrating an existing plan from elsewhere. Null when the
  /// plan starts fresh. Only offered for solo plans.
  String? _startingPointRef;

  static const Map<String, Map<String, List<String>>> _bookCategories = {
    'Old Testament': {
      'Pentateuch': [
        'Genesis',
        'Exodus',
        'Leviticus',
        'Numbers',
        'Deuteronomy',
      ],
      'Books of History': [
        'Joshua',
        'Judges',
        'Ruth',
        '1 Samuel',
        '2 Samuel',
        '1 Kings',
        '2 Kings',
        '1 Chronicles',
        '2 Chronicles',
        'Ezra',
        'Nehemiah',
        'Esther',
      ],
      'Books of Poetry': [
        'Job',
        'Psalm',
        'Proverbs',
        'Ecclesiastes',
        'Song of Songs',
      ],
      'Books of Prophecy': [
        'Isaiah',
        'Jeremiah',
        'Lamentations',
        'Ezekiel',
        'Daniel',
        'Hosea',
        'Joel',
        'Amos',
        'Obadiah',
        'Jonah',
        'Micah',
        'Nahum',
        'Habakkuk',
        'Zephaniah',
        'Haggai',
        'Zechariah',
        'Malachi',
      ],
    },
    'New Testament': {
      'Gospels': ['Matthew', 'Mark', 'Luke', 'John'],
      'History': ['Acts'],
      'Epistles': [
        'Romans',
        '1 Corinthians',
        '2 Corinthians',
        'Galatians',
        'Ephesians',
        'Philippians',
        'Colossians',
        '1 Thessalonians',
        '2 Thessalonians',
        '1 Timothy',
        '2 Timothy',
        'Titus',
        'Philemon',
        'Hebrews',
        'James',
        '1 Peter',
        '2 Peter',
        '1 John',
        '2 John',
        '3 John',
        'Jude',
      ],
      'Prophecy': ['Revelation'],
    },
  };

  final Set<String> _expandedCategories = {};

  bool get _isEditing => widget.editingPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.editingPlan;
    if (plan == null) return;

    // Pre-fill from the plan being edited so the form mirrors its current
    // configuration. Anchor the start date to the existing progress so the
    // regenerated schedule lines up with what the user has already read.
    _titleController.text = plan.title;
    _startDate = widget.editingProgress?.startDate ?? _startDate;

    final config = plan.config;
    if (config != null) {
      _selectedType = PlanType.values.firstWhere(
        (t) => t.name == config['type'],
        orElse: () => _selectedType,
      );
      _years = (config['years'] as num?)?.toInt() ?? _years;
      final end = config['endDate'] as String?;
      _endDate = end != null ? DateTime.tryParse(end) : null;
      _goalMethod = _PlanGoalMethod.values.firstWhere(
        (m) => m.name == config['goalMethod'],
        orElse: () => _goalMethod,
      );
      _customChaptersPerDay = (config['customChaptersPerDay'] as num?)?.toInt();
      _customVersesPerDay = (config['customVersesPerDay'] as num?)?.toInt();
      final days = (config['readingDays'] as List?)?.cast<num>();
      if (days != null && days.isNotEmpty) {
        _readingDays
          ..clear()
          ..addAll(days.map((d) => d.toInt()));
      }
      final books = (config['selectedBooks'] as List?)?.cast<String>();
      if (books != null) {
        _selectedBooks
          ..clear()
          ..addAll(books);
      }
      // A sequential plan with a daily amount or a subset of books was made
      // through "Choose books"; reopen it there. An end date is a Length.
      _isCustomPlanExpanded = _selectedType == PlanType.sequential &&
          (_goalMethod != _PlanGoalMethod.endDate ||
              _selectedBooks.length != ReferenceParser.allBooks.length);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  /// Snapshot of the current form configuration, persisted on the plan so the
  /// edit flow can faithfully re-populate this screen later.
  Map<String, dynamic> _buildConfig() => {
        'type': _selectedType.name,
        'years': _years > 0 ? _years : 1,
        'endDate': _goalMethod == _PlanGoalMethod.endDate
            ? _endDate?.toIso8601String()
            : null,
        'goalMethod': _goalMethod.name,
        'customChaptersPerDay': _goalMethod == _PlanGoalMethod.chaptersPerDay
            ? _customChaptersPerDay
            : null,
        'customVersesPerDay': _goalMethod == _PlanGoalMethod.versesPerDay
            ? _customVersesPerDay
            : null,
        'readingDays': _readingDays.toList()..sort(),
        'selectedBooks':
            _selectedBooks.length == ReferenceParser.allBooks.length
                ? null
                : _selectedBooks.toList(),
      };

  /// The chapter pool the current form configuration reads through, in order.
  List<String> _plannedChapters() {
    if (_selectedBooks.length == ReferenceParser.allBooks.length) {
      return ReferenceParser.allBooks;
    }
    return _selectedBooks.toList();
  }

  /// The group-shape draft equivalent of the current solo configuration, used
  /// when the reader chooses "With a group": the group's shared schedule is
  /// generated by [ScheduleGenerator] from a [GroupPlanDraft], so the solo
  /// configuration is translated into one.
  GroupPlanDraft _buildGroupDraft() {
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final books = _plannedChapters();
    final startRef = books.isEmpty ? '' : '${books.first} 1';

    const weekdaysAll = [1, 2, 3, 4, 5, 6, 7];
    final readingEveryDay = _readingDays.length == 7;

    switch (_goalMethod) {
      case _PlanGoalMethod.endDate:
        if (_endDate != null && readingEveryDay) {
          // End-date mode with daily readings maps directly.
          return GroupPlanDraft(
            books: books,
            startRef: startRef,
            mode: ScheduleMode.endDate,
            chaptersPerDay: null,
            startDate: start,
            endDate: DateTime(
              _endDate!.year,
              _endDate!.month,
              _endDate!.day,
            ),
            weekdays: weekdaysAll,
            bookBoundary: false,
            dayOverrides: const {},
          );
        }
        final spanDays = _endDate == null
            ? _years * 365
            : _endDate!.difference(start).inDays + 1;
        final activeDays = readingEveryDay
            ? spanDays
            : (spanDays * _readingDays.length / 7).ceil();
        final totalChapters = books.fold<int>(
          0,
          (total, book) => total + (ReferenceParser.chapterCount(book) ?? 0),
        );
        return GroupPlanDraft(
          books: books,
          startRef: startRef,
          mode: ScheduleMode.chaptersPerDay,
          chaptersPerDay: activeDays > 0
              ? (totalChapters / activeDays).ceil().clamp(1, 12)
              : 2,
          startDate: start,
          endDate: null,
          weekdays: _readingDays.toList()..sort(),
          bookBoundary: false,
          dayOverrides: const {},
        );
      case _PlanGoalMethod.chaptersPerDay:
        return GroupPlanDraft(
          books: books,
          startRef: startRef,
          mode: ScheduleMode.chaptersPerDay,
          chaptersPerDay: (_customChaptersPerDay ?? 2).clamp(1, 12),
          startDate: start,
          endDate: null,
          weekdays: _readingDays.toList()..sort(),
          bookBoundary: false,
          dayOverrides: const {},
        );
      case _PlanGoalMethod.versesPerDay:
        // ~26 verses per chapter, matching PlanGenerator's approximation.
        final chapters = ((_customVersesPerDay ?? 52) / 26).ceil().clamp(1, 12);
        return GroupPlanDraft(
          books: books,
          startRef: startRef,
          mode: ScheduleMode.chaptersPerDay,
          chaptersPerDay: chapters,
          startDate: start,
          endDate: null,
          weekdays: _readingDays.toList()..sort(),
          bookBoundary: false,
          dayOverrides: const {},
        );
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_readingDays.contains(day)) {
        if (_readingDays.length > 1) {
          // Prevent unselecting all
          _readingDays.remove(day);
        }
      } else {
        _readingDays.add(day);
      }
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initialDate = isStart
        ? _startDate
        : (_endDate ?? DateTime.now().add(const Duration(days: 365)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: isStart
          ? DateTime.now().subtract(const Duration(days: 365))
          : _startDate.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  surfaceContainerHigh: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
          _years = 0; // Reset years if custom end date
        }
      });
    }
  }

  /// Asks the reader where they've already read up to (ADR-0005), reusing the
  /// group plan's chapter picker. Resolves to a canonical "Book Chapter" ref.
  Future<void> _pickStartingPoint() async {
    final books = _plannedChapters();
    if (books.isEmpty) return;
    final currentRef = _startingPointRef ?? '${books.first} 1';
    final picked = await showStartChapterSheet(
      context,
      books: books,
      currentRef: currentRef,
      vibrationService: widget.vibrationService,
    );
    if (picked != null && mounted) {
      setState(() => _startingPointRef = picked);
    }
  }

  Future<void> _createPlan() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    if (_audience == PlanAudience.solo &&
        _titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a plan title.')),
      );
      return;
    }

    if (_audience == PlanAudience.group &&
        _groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please name your group.')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final planService = ReadingPlanService(firestore: widget.firestore);

      // Edit: rewrite the existing plan in place, preserving its progress.
      if (_isEditing) {
        final updated = _buildPlan(id: widget.editingPlan!.id);
        await planService.updateCustomPlan(user.uid, updated);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      if (_audience == PlanAudience.group) {
        await _createSharedPlan(user.uid);
        return;
      }

      final plan = _buildPlan(id: '');
      final planId = await planService.saveCustomPlan(user.uid, plan);

      // Auto-start the plan. A Starting point (ADR-0005) shifts the start date
      // so the reader's position lands on today, marks the days up to it, and
      // credits them to coverage silently — never announced.
      final startingPoint = _startingPointRef;
      if (startingPoint != null) {
        final parsed = ReferenceParser.parseChapterRef(startingPoint);
        final dayNumber = parsed == null
            ? null
            : _dayNumberForChapter(plan, parsed.book, parsed.chapter);
        if (dayNumber != null) {
          final shifted = await planService.startPlanWithStartingPoint(
            user.uid,
            planId,
            plan,
            dayNumber: dayNumber,
            today: DateTime.now(),
          );
          if (shifted != null) {
            await PlanCompletionCoordinator(
              firestore: widget.firestore,
            ).creditPlanDaysSilently(
              uid: user.uid,
              planId: planId,
              days: List<int>.generate(dayNumber, (i) => i + 1),
            );
          }
        } else {
          // The chapter isn't in this plan's schedule — fall back to a plain
          // start rather than silently dropping the reader's claim.
          await planService.startPlan(user.uid, planId, startDate: _startDate);
        }
      } else {
        await planService.startPlan(user.uid, planId, startDate: _startDate);
      }

      if (!mounted) return;

      // Navigate to detail page
      final savedPlan = await planService.getPlanById(planId, userId: user.uid);
      if (!mounted) return;
      if (savedPlan != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlanDetailPage(
              plan: savedPlan,
              firestore: widget.firestore,
              auth: widget.auth,
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error ${_isEditing ? 'saving' : 'creating'} '
              'plan: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  /// The "With a group" branch: creates the Group and the shared plan
  /// together in this flow, then lands the reader in it (#809).
  Future<void> _createSharedPlan(String uid) async {
    final groupService = widget.groupService ?? GroupService();
    final name = _groupNameController.text.trim();
    final draft = _buildGroupDraft();
    final generated = ScheduleGenerator.planFromDraft(draft);

    final groupId = await groupService.createGroup(
      ownerUid: uid,
      name: name,
    );
    await groupService.updateScheduleBatch(
      groupId: groupId,
      schedules: generated.days,
    );
    await groupService.updatePlanConfig(groupId: groupId, config: draft);

    if (!mounted) return;

    // The creation pages replace themselves with a detail page on success, so
    // the hub reloads when this route eventually pops (see PlansHub._enroll).
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GroupMembersPage(
          group: Group(
            id: groupId,
            name: name,
            ownerUid: uid,
            memberCount: 1,
            planConfig: draft,
          ),
          groupService: groupService,
          nudgeService: NudgeService(firestore: widget.firestore),
          auth: widget.auth,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  List<DateTime> _scheduleDates(int count) {
    final dates = <DateTime>[];
    if (count <= 0) return dates;
    var cursor = DateTime(_startDate.year, _startDate.month, _startDate.day);
    while (dates.length < count) {
      if (_readingDays.contains(cursor.weekday)) {
        dates.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  void _showFullSchedule(BuildContext context, ReadingPlan plan) {
    final colorScheme = Theme.of(context).colorScheme;
    final dates = _scheduleDates(plan.schedule.length);
    showAppSheet<void>(
      context: context,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding,
                      AppSpacing.gap16, AppSpacing.hPadding, AppSpacing.gap12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Full Schedule',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gap16, 0,
                        AppSpacing.gap16, AppSpacing.gap24),
                    itemCount: plan.schedule.length,
                    itemBuilder: (context, index) {
                      final day = plan.schedule[index];
                      final date = index < dates.length
                          ? dates[index]
                          : _startDate.add(Duration(days: day.day - 1));
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.gap8),
                        padding: const EdgeInsets.all(AppSpacing.gap12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.rInset),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${_months[date.month - 1]} ${date.day}',
                                key: Key('create_plan_schedule_date_$index'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.gap8),
                            Expanded(
                              child: Text(
                                day.readings.join(', '),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Generates the plan from the current configuration. Shared by [_createPlan]
  /// and the live preview so they never diverge.
  ReadingPlan _buildPlan({required String id}) {
    final title = _titleController.text.trim();
    final plan = PlanGenerator.generatePlan(
      id: id,
      title: title.isEmpty ? 'Preview' : _capitalizeWords(title),
      description: _generateDescription(),
      type: _selectedType,
      years: _years > 0 ? _years : 1, // Default to 1 if not set
      startDate: _startDate,
      endDate: _goalMethod == _PlanGoalMethod.endDate ? _endDate : null,
      readingDays: _readingDays.toList(),
      selectedBooks: _selectedBooks.length == ReferenceParser.allBooks.length
          ? null
          : _selectedBooks.toList(),
      customChaptersPerDay: _goalMethod == _PlanGoalMethod.chaptersPerDay
          ? _customChaptersPerDay
          : null,
      customVersesPerDay: _goalMethod == _PlanGoalMethod.versesPerDay
          ? _customVersesPerDay
          : null,
    );
    return plan.copyWith(config: _buildConfig());
  }

  /// Builds a live preview plan, returning null if the current configuration
  /// can't yet produce a schedule (e.g. no books selected mid-edit).
  ReadingPlan? _previewPlan() {
    try {
      final plan = _buildPlan(id: 'preview');
      return plan.schedule.isEmpty ? null : plan;
    } catch (_) {
      return null;
    }
  }

  String _capitalizeWords(String input) {
    if (input.isEmpty) return input;
    return input.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _generateDescription() {
    switch (_selectedType) {
      case PlanType.sequential:
        return 'Read the Bible sequentially from Genesis to Revelation.';
      case PlanType.portions:
        return 'Read portions of the Old and New Testaments daily.';
      case PlanType.threeOldOneNew:
        return 'A balanced schedule: 3 OT chapters (6 days/week) and 1 NT chapter (5 days/week).';
      case PlanType.otOnly:
        return 'Complete the Old Testament.';
      case PlanType.ntOnly:
        return 'Complete the New Testament.';
    }
  }

  /// The plan day whose readings include [book] [chapter], or null when the
  /// chapter is not scheduled in [plan].
  int? _dayNumberForChapter(ReadingPlan plan, String book, int chapter) {
    for (final day in plan.schedule) {
      for (final ref in day.readings) {
        final parsed = ReferenceParser.parseChapterRef(ref);
        if (parsed != null &&
            parsed.book == book &&
            parsed.chapter == chapter) {
          return day.day;
        }
      }
    }
    return null;
  }

  final _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  String get _startDateLabel {
    final now = DateTime.now();
    final isToday = _startDate.year == now.year &&
        _startDate.month == now.month &&
        _startDate.day == now.day;
    return isToday ? 'Today' : _formatDate(_startDate);
  }

  /// Lengths the Length stepper moves between. Whole years keep the
  /// generator's year mode (the long-standing default); anything else is
  /// expressed as an end date. Any other length — from an edited plan or the
  /// end-date picker — sits between them.
  static const _lengthSteps = [30, 60, 90, 180, 365, 730];

  /// The plan's length in calendar days as the current configuration sets it.
  int get _lengthDays {
    if (_selectedType != PlanType.threeOldOneNew &&
        _goalMethod == _PlanGoalMethod.endDate) {
      final end = _endDate;
      if (end == null) return (_years > 0 ? _years : 1) * 365;
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
      return DateTime(end.year, end.month, end.day).difference(start).inDays +
          1;
    }
    // Paced by a daily amount, or a fixed schedule: the length follows from
    // the generated plan.
    return _previewPlan()?.durationDays ?? 0;
  }

  /// Sets the plan's length, switching the pace back to length-based.
  void _setLength(int days) {
    setState(() {
      _goalMethod = _PlanGoalMethod.endDate;
      if (days % 365 == 0) {
        _years = days ~/ 365;
        _endDate = null;
      } else {
        _years = 0;
        _endDate = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day + days - 1,
        );
      }
    });
  }

  /// Picks a reading method. "Choose books" is the sequential reading with
  /// the book picker and daily-amount options open; leaving it goes back to
  /// the whole Bible paced by length.
  void _selectReading(PlanType type, {bool chooseBooks = false}) {
    unawaited(widget.vibrationService.lightImpact());
    setState(() {
      _selectedType = type;
      if (type == PlanType.threeOldOneNew) {
        _years = 1;
      }
      if (chooseBooks) {
        _isCustomPlanExpanded = true;
      } else if (_isCustomPlanExpanded) {
        _isCustomPlanExpanded = false;
        _selectedBooks
          ..clear()
          ..addAll(ReferenceParser.allBooks);
        _goalMethod = _PlanGoalMethod.endDate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SubHeader(
              title: _isEditing ? 'Edit plan' : 'New plan',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.hPadding,
                  0,
                  AppSpacing.hPadding,
                  AppSpacing.gap16,
                ),
                children: [
                  // Who's reading — a field, not a fork (#809). Hidden while
                  // editing: an existing plan's audience never changes.
                  if (!_isEditing)
                    _section(
                      context,
                      "Who's reading",
                      _buildAudienceSection(context),
                      first: true,
                    ),
                  // A Shared plan has no title of its own: the Group name
                  // above is its only name.
                  if (_audience == PlanAudience.solo)
                    _section(
                      context,
                      'Name',
                      TextField(
                        key: const Key('create_plan_title'),
                        controller: _titleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'e.g., Daily Walk',
                        ),
                      ),
                      first: _isEditing,
                    ),
                  _section(context, 'What to read', _buildReadingCard(context)),
                  _section(context, 'Pace', _buildPaceCard(context)),
                  _section(context, 'Start', _buildStartCard(context)),
                  const SizedBox(height: AppSpacing.gap8),
                  _buildPreviewLine(context),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: appColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.hPadding,
          AppSpacing.gap12,
          AppSpacing.hPadding,
          AppSpacing.gap12,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: AnimatedActionButton(
              key: const Key('create_plan_submit'),
              onPressed: _createPlan,
              isLoading: _isCreating,
              enableHapticFeedback: false,
              child: Text(_isEditing ? 'Save changes' : 'Start plan'),
            ),
          ),
        ),
      ),
    );
  }

  /// A titled section of the form: serif section title, then its content.
  Widget _section(
    BuildContext context,
    String title,
    Widget child, {
    bool first = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: first ? AppSpacing.gap8 : AppSpacing.gap24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTextStyles.sectionTitle(context)),
          const SizedBox(height: AppSpacing.gap12),
          child,
        ],
      ),
    );
  }

  /// A surface card holding rows separated by dividers.
  Widget _card(BuildContext context, List<Widget> children) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// "Just you" / "With a group", with the group name once a group is chosen.
  Widget _buildAudienceSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.gap4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppSpacing.rPill),
          ),
          child: Row(
            children: [
              _audienceSegment(context, PlanAudience.solo, 'Just you'),
              _audienceSegment(context, PlanAudience.group, 'With a group'),
            ],
          ),
        ),
        if (_audience == PlanAudience.group) ...[
          const SizedBox(height: AppSpacing.gap12),
          TextField(
            key: const Key('create_plan_group_name'),
            controller: _groupNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'e.g., Thursday morning group',
            ),
          ),
        ],
      ],
    );
  }

  Widget _audienceSegment(
    BuildContext context,
    PlanAudience value,
    String label,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = _audience == value;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            unawaited(widget.vibrationService.lightImpact());
            setState(() => _audience = value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: AppSpacing.gap40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.surfaceContainerLowest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.rPill),
              boxShadow: selected ? AppSpacing.cardShadow(context) : null,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The reading methods as one list of radio rows.
  Widget _buildReadingCard(BuildContext context) {
    bool isType(PlanType type) =>
        !_isCustomPlanExpanded && _selectedType == type;

    return _card(context, [
      _readingRow(
        context,
        title: 'In order',
        subtitle: 'Genesis to Revelation',
        selected: isType(PlanType.sequential),
        onTap: () => _selectReading(PlanType.sequential),
      ),
      const Divider(height: 1),
      _readingRow(
        context,
        title: 'Balanced',
        subtitle: 'Old and New Testament each day',
        selected: isType(PlanType.portions),
        onTap: () => _selectReading(PlanType.portions),
      ),
      const Divider(height: 1),
      _readingRow(
        context,
        title: '3 in Old, 1 in New',
        subtitle: 'A fixed daily distribution',
        selected: isType(PlanType.threeOldOneNew),
        onTap: () => _selectReading(PlanType.threeOldOneNew),
      ),
      const Divider(height: 1),
      _readingRow(
        context,
        title: 'Old Testament',
        subtitle: 'Genesis to Malachi',
        selected: isType(PlanType.otOnly),
        onTap: () => _selectReading(PlanType.otOnly),
      ),
      const Divider(height: 1),
      _readingRow(
        context,
        title: 'New Testament',
        subtitle: 'Matthew to Revelation',
        selected: isType(PlanType.ntOnly),
        onTap: () => _selectReading(PlanType.ntOnly),
      ),
      const Divider(height: 1),
      _readingRow(
        context,
        title: 'Choose books',
        subtitle: 'Pick exactly what to read',
        selected: _isCustomPlanExpanded,
        onTap: () => _selectReading(PlanType.sequential, chooseBooks: true),
      ),
      if (_isCustomPlanExpanded) _buildChooseBooks(context),
    ]);
  }

  Widget _readingRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.gap12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.gap2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              _radio(context, selected, size: AppSpacing.iconMd),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radio(BuildContext context, bool selected, {required double size}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? size * 0.3 : 1.5,
        ),
      ),
    );
  }

  /// The "Choose books" flow: the book picker and the daily-amount pace.
  Widget _buildChooseBooks(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        0,
        AppSpacing.cardPadding,
        AppSpacing.cardPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._bookCategories.entries.map(
            (entry) => _buildBookCategory(entry.key, entry.value),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Text('Pace by', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.gap4),
          _buildGoalOption(_PlanGoalMethod.endDate, 'Length'),
          _buildGoalOption(
            _PlanGoalMethod.chaptersPerDay,
            'Chapters a day',
            stepper: _RoundStepper(
              value: '${_customChaptersPerDay ?? 1}',
              decrementLabel: 'One chapter fewer',
              incrementLabel: 'One chapter more',
              decrementKey: const Key('create_plan_chapters_dec'),
              incrementKey: const Key('create_plan_chapters_inc'),
              onDecrement: (_customChaptersPerDay ?? 1) > 1
                  ? () => setState(
                        () =>
                            _customChaptersPerDay = _customChaptersPerDay! - 1,
                      )
                  : null,
              onIncrement: (_customChaptersPerDay ?? 1) < _maxChaptersPerDay
                  ? () => setState(
                        () => _customChaptersPerDay =
                            (_customChaptersPerDay ?? 1) + 1,
                      )
                  : null,
              vibrationService: widget.vibrationService,
            ),
          ),
          _buildGoalOption(
            _PlanGoalMethod.versesPerDay,
            'Verses a day',
            stepper: _RoundStepper(
              value: '${_customVersesPerDay ?? _verseStep}',
              decrementLabel: '$_verseStep verses fewer',
              incrementLabel: '$_verseStep verses more',
              decrementKey: const Key('create_plan_verses_dec'),
              incrementKey: const Key('create_plan_verses_inc'),
              onDecrement: (_customVersesPerDay ?? _verseStep) > _verseStep
                  ? () => setState(
                        () => _customVersesPerDay =
                            _customVersesPerDay! - _verseStep,
                      )
                  : null,
              onIncrement: (_customVersesPerDay ?? _verseStep) <
                      _maxVersesPerDay
                  ? () => setState(
                        () => _customVersesPerDay =
                            (_customVersesPerDay ?? _verseStep) + _verseStep,
                      )
                  : null,
              vibrationService: widget.vibrationService,
            ),
          ),
        ],
      ),
    );
  }

  static const _maxChaptersPerDay = 20;
  static const _verseStep = 5;
  static const _maxVersesPerDay = 200;

  Widget _buildGoalOption(
    _PlanGoalMethod method,
    String label, {
    Widget? stepper,
  }) {
    final isSelected = _goalMethod == method;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      checked: isSelected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.rChip),
        onTap: () {
          unawaited(widget.vibrationService.lightImpact());
          setState(() {
            _goalMethod = method;
            // A daily amount starts from a sensible value instead of empty.
            if (method == _PlanGoalMethod.chaptersPerDay) {
              _customChaptersPerDay ??= 3;
            } else if (method == _PlanGoalMethod.versesPerDay) {
              _customVersesPerDay ??= 25;
            }
          });
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              _radio(context, isSelected, size: 18),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isSelected && stepper != null) stepper,
            ],
          ),
        ),
      ),
    );
  }

  /// Length stepper and reading-day chips.
  Widget _buildPaceCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fixed = _selectedType == PlanType.threeOldOneNew;
    final length = _lengthDays;
    final shorter = _lengthSteps.lastWhere(
      (days) => days < length,
      orElse: () => 0,
    );
    final longer = _lengthSteps.firstWhere(
      (days) => days > length,
      orElse: () => 0,
    );

    return _card(context, [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.gap12,
        ),
        child: Row(
          children: [
            Expanded(child: Text('Length', style: theme.textTheme.titleMedium)),
            _RoundStepper(
              value: '$length days',
              decrementLabel: 'Shorter',
              incrementLabel: 'Longer',
              decrementKey: const Key('create_plan_length_dec'),
              incrementKey: const Key('create_plan_length_inc'),
              valueKey: const Key('create_plan_length'),
              onDecrement:
                  fixed || shorter == 0 ? null : () => _setLength(shorter),
              onIncrement:
                  fixed || longer == 0 ? null : () => _setLength(longer),
              // Any other length: pick the end date directly.
              onTapValue: fixed
                  ? null
                  : () async {
                      final before = _endDate;
                      await _selectDate(context, false);
                      if (mounted && _endDate != before) {
                        setState(() => _goalMethod = _PlanGoalMethod.endDate);
                      }
                    },
              vibrationService: widget.vibrationService,
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: fixed
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: AppSpacing.iconSm,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.gap8),
                  Expanded(
                    child: Text(
                      'To complete this schedule in one year, you must read three OT chapters on six days and one NT chapter on five days. Choose another schedule type to specify days.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reading days', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.gap12),
                  Row(
                    children: [
                      _dayChip(7, 'S'), // Sun
                      _dayChip(1, 'M'), // Mon
                      _dayChip(2, 'T'), // Tue
                      _dayChip(3, 'W'), // Wed
                      _dayChip(4, 'T'), // Thu
                      _dayChip(5, 'F'), // Fri
                      _dayChip(6, 'S'), // Sat
                    ],
                  ),
                ],
              ),
      ),
    ]);
  }

  String _fullDayName(int day) {
    const days = {
      7: 'Sunday',
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
    };
    return days[day] ?? '';
  }

  Widget _dayChip(int day, String label) {
    final isSelected = _readingDays.contains(day);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Semantics(
        checked: isSelected,
        button: true,
        label: _fullDayName(day),
        child: GestureDetector(
          key: Key('create_plan_day_$day'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            unawaited(widget.vibrationService.lightImpact());
            _toggleDay(day);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gap2,
              vertical: AppSpacing.gap2,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.gap40),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerLow,
                      border: isSelected
                          ? null
                          : Border.all(color: AppColors.of(context).border),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Start date and Starting point. Both are fixed while editing: the
  /// schedule is anchored to the plan's existing progress, so it must not
  /// drift out from under recorded readings.
  Widget _buildStartCard(BuildContext context) {
    return _card(context, [
      _valueRow(
        context,
        key: const Key('create_plan_start_date'),
        label: 'Start date',
        value: _startDateLabel,
        onTap: _isEditing ? null : () => _selectDate(context, true),
      ),
      const Divider(height: 1),
      // Starting point (ADR-0005): "I've already read up to this chapter"
      // when migrating an existing plan from elsewhere. Shifts the start date
      // so the position lands on today and marks the days up to it.
      _valueRow(
        context,
        key: const Key('create_plan_starting_point'),
        label: 'Starting point',
        value: _startingPointRef ?? 'Start fresh',
        onTap: _isEditing ? null : _pickStartingPoint,
      ),
    ]);
  }

  Widget _valueRow(
    BuildContext context, {
    required Key key,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;

    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.gap16,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: AppSpacing.gap4),
              Icon(
                Icons.chevron_right,
                size: AppSpacing.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One line saying where the current configuration lands; tapping it opens
  /// the full schedule.
  Widget _buildPreviewLine(BuildContext context) {
    final plan = _previewPlan();
    if (plan == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final dates = _scheduleDates(plan.schedule.length);
    final end = dates.isNotEmpty
        ? dates.last
        : DateTime(
            _startDate.year,
            _startDate.month,
            _startDate.day + plan.schedule.last.day - 1,
          );
    final chapters = plan.schedule.fold<int>(
      0,
      (total, day) => total + day.readings.length,
    );
    final perDay = (chapters / plan.schedule.length).round().clamp(1, chapters);

    return Semantics(
      button: true,
      hint: 'View full schedule',
      child: InkWell(
        key: const Key('create_plan_preview'),
        borderRadius: BorderRadius.circular(AppSpacing.rChip),
        onTap: () => _showFullSchedule(context, plan),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap4,
            vertical: AppSpacing.gap12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ends ${_formatDate(end)} · about $perDay '
                  '${perDay == 1 ? 'chapter' : 'chapters'} a day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.gap4),
              Icon(
                Icons.chevron_right,
                size: AppSpacing.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookCategory(
    String name,
    Map<String, List<String>> subcategories,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final allBooksInCategory = subcategories.values.expand((e) => e).toList();
    final isFullySelected = allBooksInCategory.every(
      (book) => _selectedBooks.contains(book),
    );
    final isPartiallySelected =
        allBooksInCategory.any((book) => _selectedBooks.contains(book)) &&
            !isFullySelected;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.gap8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              key: Key('create_plan_category_$name'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () {
                setState(() {
                  if (_expandedCategories.contains(name)) {
                    _expandedCategories.remove(name);
                  } else {
                    _expandedCategories.add(name);
                  }
                });
              },
              leading: Checkbox(
                visualDensity: VisualDensity.compact,
                value: isFullySelected
                    ? true
                    : (isPartiallySelected ? null : false),
                tristate: true,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedBooks.addAll(allBooksInCategory);
                    } else {
                      _selectedBooks.removeWhere(
                        (book) => allBooksInCategory.contains(book),
                      );
                    }
                  });
                },
              ),
              title: Text(
                name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              trailing: Icon(
                _expandedCategories.contains(name)
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: AppSpacing.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_expandedCategories.contains(name))
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.gap16,
                  bottom: AppSpacing.gap8,
                ),
                child: Column(
                  children: subcategories.entries
                      .map((e) => _buildBookSubcategory(e.key, e.value))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookSubcategory(String name, List<String> books) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFullySelected = books.every(
      (book) => _selectedBooks.contains(book),
    );
    final isPartiallySelected =
        books.any((book) => _selectedBooks.contains(book)) && !isFullySelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Checkbox(
            visualDensity: VisualDensity.compact,
            value:
                isFullySelected ? true : (isPartiallySelected ? null : false),
            tristate: true,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedBooks.addAll(books);
                } else {
                  _selectedBooks.removeWhere((book) => books.contains(book));
                }
              });
            },
          ),
          title: Text(
            name,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.onSurface),
          ),
          trailing: Icon(
            _expandedCategories.contains(name)
                ? Icons.expand_less
                : Icons.expand_more,
            size: AppSpacing.iconMd,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () {
            setState(() {
              if (_expandedCategories.contains(name)) {
                _expandedCategories.remove(name);
              } else {
                _expandedCategories.add(name);
              }
            });
          },
        ),
        if (_expandedCategories.contains(name))
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.gap32),
            child: Column(
              children: books.map((book) {
                final isSelected = _selectedBooks.contains(book);
                return ListTile(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedBooks.remove(book);
                      } else {
                        _selectedBooks.add(book);
                      }
                    });
                  },
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedBooks.add(book);
                        } else {
                          _selectedBooks.remove(book);
                        }
                      });
                    },
                  ),
                  title: Text(
                    book,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isSelected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

/// A minus / value / plus control with round 40px buttons and a serif value,
/// used for the plan's length and its daily amount. A null callback dims and
/// disables that button.
class _RoundStepper extends StatelessWidget {
  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback? onTapValue;
  final String decrementLabel;
  final String incrementLabel;
  final Key? decrementKey;
  final Key? incrementKey;
  final Key? valueKey;
  final VibrationService vibrationService;

  const _RoundStepper({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    required this.decrementLabel,
    required this.incrementLabel,
    required this.vibrationService,
    this.onTapValue,
    this.decrementKey,
    this.incrementKey,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      key: valueKey,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
            context, decrementKey, Icons.remove, decrementLabel, onDecrement),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 84),
          child: onTapValue == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gap8,
                  ),
                  child: valueText,
                )
              : InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.rChip),
                  onTap: onTapValue,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gap8,
                      vertical: AppSpacing.gap8,
                    ),
                    child: valueText,
                  ),
                ),
        ),
        _button(context, incrementKey, Icons.add, incrementLabel, onIncrement),
      ],
    );
  }

  Widget _button(
    BuildContext context,
    Key? key,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        key: key,
        color: colorScheme.surfaceContainerLow,
        shape: CircleBorder(
          side: BorderSide(color: AppColors.of(context).border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  unawaited(vibrationService.lightImpact());
                  onTap();
                }
              : null,
          child: SizedBox(
            width: AppSpacing.gap40,
            height: AppSpacing.gap40,
            child: Icon(
              icon,
              size: AppSpacing.iconSm,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}
