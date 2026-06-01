import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/plan_generator.dart';
import '../services/reading_plan_service.dart';
import '../services/reference_parser.dart';
import 'plan_detail_page.dart';

enum _PlanGoalMethod { endDate, versesPerDay, chaptersPerDay }

class CreatePlanPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const CreatePlanPage({
    super.key,
    required this.firestore,
    required this.auth,
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

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
      final plan = PlanGenerator.generatePlan(
        id: '', // Will be set by Firestore
        title: _capitalizeWords(_titleController.text.trim()),
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

      final planService = ReadingPlanService(firestore: widget.firestore);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating plan: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
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
        title: const Text(
          'Enroll in New Plan',
          style: TextStyle(fontWeight: FontWeight.w600),
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
                    borderRadius: BorderRadius.circular(24),
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
                              borderRadius: BorderRadius.circular(24),
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
                        onTap: () => _selectDate(context, true),
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
                    borderRadius: BorderRadius.circular(24),
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
                        onTap: () => _selectDate(context, true),
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
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
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
                    : const Text(
                        'Start My Plan',
                        style: TextStyle(
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

    return GestureDetector(
      onTap: () => setState(() {
        _selectedType = type;
        if (type == PlanType.threeOldOneNew) {
          _years = 1;
        }
      }),
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
                  color: colorScheme.primaryContainer.withValues(alpha: 0.2),
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
    );
  }

  Widget _dayCircle(int day, String label) {
    final isSelected = _readingDays.contains(day);
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _toggleDay(day),
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
        GestureDetector(
          onTap: () => setState(() => _goalMethod = method),
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
