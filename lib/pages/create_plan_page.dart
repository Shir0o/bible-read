import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/catch_up_engine.dart';
import '../services/plan_generator.dart';
import '../services/reading_plan_service.dart';
import '../services/reference_parser.dart';
import '../services/vibration_service.dart';
import '../widgets/schedule_preview.dart';
import 'plan_detail_page.dart';

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

  const CreatePlanPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.vibrationService = const VibrationService(),
    this.editingPlan,
    this.editingProgress,
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
  bool _isCreating = false;
  bool _isCustomPlanExpanded = false;

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
      // Surface the custom panel when the plan used a non-default goal/books.
      _isCustomPlanExpanded = _goalMethod != _PlanGoalMethod.endDate ||
          _endDate != null ||
          _selectedBooks.length != ReferenceParser.allBooks.length;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  Future<void> _createPlan() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a plan title.')),
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

      final plan = _buildPlan(id: '');
      final planId = await planService.saveCustomPlan(user.uid, plan);

      // Auto-start the plan
      await planService.startPlan(user.uid, planId, startDate: _startDate);

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

  /// Live preview card reflecting the current configuration.
  Widget _buildPreviewSection(BuildContext context) {
    final plan = _previewPlan();
    if (plan == null) return const SizedBox.shrink();

    final status = CatchUpEngine.forPersonalPlan(
      plan,
      UserPlanProgress(
        planId: plan.id,
        userId: '',
        startDate: _startDate,
        completedDays: const [],
      ),
      today: DateTime.now(),
    );

    return SchedulePreview(
      status: status,
      title: 'Preview',
      onViewFull: () => _showFullSchedule(context, plan),
    );
  }

  void _showFullSchedule(BuildContext context, ReadingPlan plan) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      backgroundColor: colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: plan.schedule.length,
                    itemBuilder: (context, index) {
                      final day = plan.schedule[index];
                      final date = _startDate.add(Duration(days: day.day - 1));
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${_months[date.month - 1]} ${date.day}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Plan' : 'Enroll in New Plan',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 100,
            ), // padding for bottom button
            children: [
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Plan Title',
                  hintText: 'e.g., Daily Walk',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'SELECT READING METHOD',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              _buildPlanTypeOption(
                PlanType.sequential,
                'Sequentially',
                'Read from Genesis to Revelation',
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.portions,
                'Old & New Testaments',
                'Balanced daily portions from both',
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.threeOldOneNew,
                '3 in Old, 1 in New',
                'Fixed daily distribution',
                showInfo: true,
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.otOnly,
                'Old Testament Only',
                'Genesis to Malachi',
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.ntOnly,
                'New Testament Only',
                'Matthew to Revelation',
              ),
              const SizedBox(height: 24),

              // Configuration Section
              if (_selectedType != PlanType.threeOldOneNew) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.rCard),
                  ),
                  child: Column(
                    children: [
                      // Duration Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Plan Duration',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.rCard,
                              ),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _years = 1;
                                    _endDate = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _years == 1
                                          ? colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '1 Year',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _years == 1
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _years = 2;
                                    _endDate = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _years == 2
                                          ? colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '2 Years',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _years == 2
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Day Selection
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Active Reading Days',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _dayCircle(7, 'S'), // Sun
                          _dayCircle(1, 'M'), // Mon
                          _dayCircle(2, 'T'), // Tue
                          _dayCircle(3, 'W'), // Wed
                          _dayCircle(4, 'T'), // Thu
                          _dayCircle(5, 'F'), // Fri
                          _dayCircle(6, 'S'), // Sat
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Start Date
                      InkWell(
                        // When editing, the start date is fixed: the schedule
                        // is anchored to the plan's existing progress, so it
                        // must not drift out from under recorded readings.
                        onTap: _isEditing
                            ? null
                            : () => _selectDate(context, true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                const Text('Start Date'),
                              ],
                            ),
                            Text(
                              '${_months[_startDate.month - 1]} ${_startDate.day}, ${_startDate.year}',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Fixed configuration for 3 in Old, 1 in New
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.rCard),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Plan Duration',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '1 Year',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      InkWell(
                        // When editing, the start date is fixed: the schedule
                        // is anchored to the plan's existing progress, so it
                        // must not drift out from under recorded readings.
                        onTap: _isEditing
                            ? null
                            : () => _selectDate(context, true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                const Text('Start Date'),
                              ],
                            ),
                            Text(
                              '${_months[_startDate.month - 1]} ${_startDate.day}, ${_startDate.year}',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Custom Plan Section
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  border: Border.all(
                    color: AppColors.of(context).border,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.rCard),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.rCard),
                      onTap: () {
                        setState(() {
                          _isCustomPlanExpanded = !_isCustomPlanExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.tune,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Custom Plan',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Icon(
                              _isCustomPlanExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isCustomPlanExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildGoalOption(
                              _PlanGoalMethod.endDate,
                              'End date:',
                              InkWell(
                                onTap: _goalMethod == _PlanGoalMethod.endDate
                                    ? () => _selectDate(context, false)
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _goalMethod ==
                                                _PlanGoalMethod.endDate
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        _endDate != null
                                            ? '${_months[_endDate!.month - 1]} ${_endDate!.day}, ${_endDate!.year}'
                                            : 'Select Date',
                                        style: TextStyle(
                                          color: _goalMethod ==
                                                  _PlanGoalMethod.endDate
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: _goalMethod ==
                                                _PlanGoalMethod.endDate
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildGoalOption(
                              _PlanGoalMethod.versesPerDay,
                              'Amount of verses to read per day:',
                              _buildNumericField(
                                value: _customVersesPerDay,
                                onChanged: (val) => setState(
                                  () => _customVersesPerDay = int.tryParse(val),
                                ),
                                enabled:
                                    _goalMethod == _PlanGoalMethod.versesPerDay,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildGoalOption(
                              _PlanGoalMethod.chaptersPerDay,
                              'Amount of chapters to read per day:',
                              _buildNumericField(
                                value: _customChaptersPerDay,
                                onChanged: (val) => setState(
                                  () =>
                                      _customChaptersPerDay = int.tryParse(val),
                                ),
                                enabled: _goalMethod ==
                                    _PlanGoalMethod.chaptersPerDay,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Select Bible books to read:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._bookCategories.entries.map(
                              (entry) =>
                                  _buildBookCategory(entry.key, entry.value),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildPreviewSection(context),
            ],
          ),

          // Bottom Action
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: FilledButton(
                onPressed: _isCreating ? null : _createPlan,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: _isCreating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: colorScheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isEditing ? 'Save Changes' : 'Start My Plan',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTypeOption(
    PlanType type,
    String title,
    String subtitle, {
    bool showInfo = false,
  }) {
    final isSelected = _selectedType == type;
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      checked: isSelected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: '$title, $subtitle',
      child: GestureDetector(
        onTap: () {
          unawaited(widget.vibrationService.lightImpact());
          setState(() {
            _selectedType = type;
            if (type == PlanType.threeOldOneNew) {
              _years = 1;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: isSelected ? 6 : 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (showInfo && isSelected) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To complete this schedule in one year, you must read three OT chapters on six days and one NT chapter on five days. Choose another schedule type to specify days.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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

  Widget _dayCircle(int day, String label) {
    final isSelected = _readingDays.contains(day);
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      checked: isSelected,
      button: true,
      label: _fullDayName(day),
      child: GestureDetector(
        onTap: () {
          unawaited(widget.vibrationService.lightImpact());
          _toggleDay(day);
        },
        child: Container(
          width: 48,
          height: 48,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalOption(
    _PlanGoalMethod method,
    String label,
    Widget inputField,
  ) {
    final isSelected = _goalMethod == method;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          checked: isSelected,
          inMutuallyExclusiveGroup: true,
          button: true,
          label: label,
          child: GestureDetector(
            onTap: () {
              unawaited(widget.vibrationService.lightImpact());
              setState(() => _goalMethod = method);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.transparent,
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: isSelected ? 5.5 : 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(left: 30), child: inputField),
      ],
    );
  }

  Widget _buildNumericField({
    int? value,
    required ValueChanged<String> onChanged,
    required bool enabled,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: enabled ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? colorScheme.outline : colorScheme.outlineVariant,
        ),
      ),
      child: TextField(
        enabled: enabled,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Enter amount',
          hintStyle: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant.withAlpha(150),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: InputBorder.none,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
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
                activeColor: colorScheme.primary,
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              trailing: Icon(
                _expandedCategories.contains(name)
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_expandedCategories.contains(name))
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
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
          title: Text(name, style: const TextStyle(fontSize: 13)),
          trailing: Icon(
            _expandedCategories.contains(name)
                ? Icons.expand_less
                : Icons.expand_more,
            size: 18,
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
            padding: const EdgeInsets.only(left: 32),
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
                    activeColor: colorScheme.primary,
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
                    style: TextStyle(
                      fontSize: 12,
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
