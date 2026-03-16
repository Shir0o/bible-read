import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/plan_generator.dart';
import '../services/reading_plan_service.dart';
import '../services/reference_parser.dart';
import 'plan_detail_page.dart';

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
  final Set<int> _readingDays = {1, 2, 3, 4, 5, 6, 7}; // 1 = Mon, 7 = Sun
  final Set<String> _selectedBooks = Set.from(ReferenceParser.allBooks);
  int? _customChaptersPerDay;
  bool _isCreating = false;
  bool _isCustomPlanExpanded = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _toggleDay(int day) {
    setState(() {
      if (_readingDays.contains(day)) {
        if (_readingDays.length > 1) { // Prevent unselecting all
          _readingDays.remove(day);
        }
      } else {
        _readingDays.add(day);
      }
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : (_endDate ?? DateTime.now().add(const Duration(days: 365)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: isStart ? DateTime.now().subtract(const Duration(days: 365)) : _startDate.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
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
        title: _titleController.text.trim(),
        description: _generateDescription(),
        type: _selectedType,
        years: _years > 0 ? _years : 1, // Default to 1 if not set
        startDate: _startDate,
        endDate: _endDate,
        readingDays: _readingDays.toList(),
        selectedBooks: _selectedBooks.length == ReferenceParser.allBooks.length ? null : _selectedBooks.toList(),
        customChaptersPerDay: _customChaptersPerDay,
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
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating plan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  String _generateDescription() {
    switch (_selectedType) {
      case PlanType.sequential:
        return 'Read the Bible sequentially from Genesis to Revelation.';
      case PlanType.portions:
        return 'Read portions of the Old and New Testaments daily.';
      case PlanType.threeOldOneNew:
        return 'A balanced schedule: 3 OT chapters (6 days/week) and 1 NT chapter (5 days/week).';
      case PlanType.otHalfYear:
        return 'Complete the Old Testament in six months.';
      case PlanType.ntHalfYear:
        return 'Complete the New Testament in six months.';
    }
  }

  final _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll in New Plan', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100), // padding for bottom button
            children: [
              TextField(
                controller: _titleController,
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
                'Read from Genesis to Revelation'
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.portions,
                'Old & New Testaments',
                'Balanced daily portions from both'
              ),
              const SizedBox(height: 8),
              _buildPlanTypeOption(
                PlanType.threeOldOneNew,
                '3 in Old, 1 in New',
                'Fixed daily distribution',
                showInfo: true,
              ),
              const SizedBox(height: 24),

              // Configuration Section
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
                        const Text('Plan Duration', style: TextStyle(fontWeight: FontWeight.w500)),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  _years = 1;
                                  _endDate = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _years == 1 ? colorScheme.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '1 Year',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _years == 1 ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
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
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _years == 2 ? colorScheme.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '2 Years',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _years == 2 ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
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
                        const Text('Active Reading Days', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8), // For spacing
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
                              Icon(Icons.calendar_today_outlined, size: 20, color: colorScheme.onSurfaceVariant),
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

              const SizedBox(height: 24),

              // Old Testament Plans
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'OLD TESTAMENT PLANS',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildHalfYearOption(PlanType.otHalfYear, '1 Year (Half-paced)', _years == 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHalfYearOption(PlanType.otHalfYear, '2 Years (Half-paced)', _years == 2),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // New Testament Plans
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'NEW TESTAMENT PLANS',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildHalfYearOption(PlanType.ntHalfYear, '1 Year (Half-paced)', _years == 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHalfYearOption(PlanType.ntHalfYear, '2 Years (Half-paced)', _years == 2),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Custom Plan Section
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
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
                                Icon(Icons.tune, color: colorScheme.primary, size: 20),
                                const SizedBox(width: 12),
                                const Text('Custom Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Icon(
                              _isCustomPlanExpanded ? Icons.expand_less : Icons.expand_more,
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
                          children: [
                            // End Date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('End Date', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                                InkWell(
                                  onTap: () => _selectDate(context, false),
                                  child: Container(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: colorScheme.primary)),
                                    ),
                                    child: Text(
                                      _endDate != null
                                          ? '${_months[_endDate!.month - 1]} ${_endDate!.day}, ${_endDate!.year}'
                                          : 'Select Date',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Chapters per Day
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Chapters per Day', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _customChaptersPerDay = (_customChaptersPerDay ?? 3) - 1;
                                          if (_customChaptersPerDay! < 1) _customChaptersPerDay = 1;
                                        });
                                      },
                                      child: Container(
                                        width: 24, height: 24,
                                        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                                        child: const Center(child: Text('-', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('${_customChaptersPerDay ?? 3}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _customChaptersPerDay = (_customChaptersPerDay ?? 3) + 1;
                                        });
                                      },
                                      child: Container(
                                        width: 24, height: 24,
                                        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                                        child: const Center(child: Text('+', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Books Included
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Books Included (${_selectedBooks.length}/${ReferenceParser.allBooks.length})',
                                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          if (_selectedBooks.isEmpty) {
                                            _selectedBooks.addAll(ReferenceParser.allBooks);
                                          } else {
                                            _selectedBooks.clear();
                                          }
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        _selectedBooks.isEmpty ? 'SELECT ALL' : 'DESELECT ALL',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ..._selectedBooks.take(3).map((b) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(b, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: colorScheme.onPrimaryContainer)),
                                    )),
                                    if (_selectedBooks.length > 3)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('...and ${_selectedBooks.length - 3} more',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
                                      ),
                                    if (_selectedBooks.isEmpty)
                                      Text('No books selected', style: TextStyle(fontSize: 12, color: colorScheme.error)),
                                  ],
                                ),
                              ],
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
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2))),
              ),
              child: FilledButton(
                onPressed: _isCreating ? null : _createPlan,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                ),
                child: _isCreating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Start My Plan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTypeOption(PlanType type, String title, String subtitle, {bool showInfo = false}) {
    final isSelected = _selectedType == type;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedType = type;
        if (type == PlanType.otHalfYear || type == PlanType.ntHalfYear) {
            // keep years
        } else {
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
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
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
                    Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
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

  Widget _buildHalfYearOption(PlanType type, String title, bool isSelectedDuration) {
    final isSelected = _selectedType == type && isSelectedDuration;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedType = type;
        _years = title.contains('2') ? 2 : 1;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorScheme.primary.withValues(alpha: 0.5) : colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '${title.split(' ')[0]} ${title.split(' ')[1]}', // '1 Year' or '2 Years'
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
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
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
