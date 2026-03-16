import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/reading_plan_service.dart';
import '../services/plan_generator.dart';
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
  PlanType _selectedType = PlanType.sequential;
  int _years = 1;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  List<int> _readingDays = [1, 2, 3, 4, 5, 6, 7]; // All days by default
  List<String> _selectedBooks = ReferenceParser.allBooks.toList();
  int? _customChaptersPerDay;
  
  bool _isCreating = false;
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.text = "My Reading Plan";
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _toggleDay(int day) {
    setState(() {
      if (_readingDays.contains(day)) {
        if (_readingDays.length > 1) {
          _readingDays.remove(day);
        }
      } else {
        _readingDays.add(day);
      }
      _readingDays.sort();
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? _startDate.add(const Duration(days: 365))),
      firstDate: isStart ? DateTime.now().subtract(const Duration(days: 30)) : _startDate.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _showBookSelection() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Books'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ReferenceParser.allBooks.length,
                  itemBuilder: (context, index) {
                    final book = ReferenceParser.allBooks[index];
                    final isSelected = _selectedBooks.contains(book);
                    return CheckboxListTile(
                      title: Text(book),
                      value: isSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            _selectedBooks.add(book);
                          } else {
                            _selectedBooks.remove(book);
                          }
                        });
                        setState(() {}); // Update main page UI count
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _selectedBooks = ReferenceParser.allBooks.toList());
                    setDialogState(() {});
                  },
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createPlan() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    setState(() => _isCreating = true);

    try {
      final plan = PlanGenerator.generatePlan(
        id: '', // Will be set by Firestore
        title: _titleController.text,
        description: _generateDescription(),
        type: _selectedType,
        years: _years,
        startDate: _startDate,
        endDate: _endDate,
        readingDays: _readingDays,
        selectedBooks: _selectedBooks.length == ReferenceParser.allBooks.length ? null : _selectedBooks,
        customChaptersPerDay: _customChaptersPerDay,
      );

      final planService = ReadingPlanService(firestore: widget.firestore);
      final planId = await planService.saveCustomPlan(user.uid, plan);
      
      // Auto-start the plan
      await planService.startPlan(user.uid, planId, startDate: _startDate);

      if (!mounted) return;

      // Navigate to detail page
      final savedPlan = await planService.getPlanById(planId, userId: user.uid);
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
        return "Read the Bible sequentially from Genesis to Revelation.";
      case PlanType.portions:
        return "Read portions of the Old and New Testaments daily.";
      case PlanType.threeOldOneNew:
        return "A balanced schedule: 3 OT chapters (6 days/week) and 1 NT chapter (5 days/week).";
      case PlanType.otHalfYear:
        return "Complete the Old Testament in six months.";
      case PlanType.ntHalfYear:
        return "Complete the New Testament in six months.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Reading Plan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Plan Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          
          Text('Plan Template', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildPlanTypeOption(
            PlanType.sequential, 
            'Sequentially', 
            'Read book by book, start to finish.'
          ),
          _buildPlanTypeOption(
            PlanType.portions, 
            'OT & NT Portions', 
            'Daily readings from both testaments.'
          ),
          _buildPlanTypeOption(
            PlanType.threeOldOneNew, 
            '3 OT + 1 NT', 
            'Specific weekly rhythm to finish in one year.'
          ),
          _buildPlanTypeOption(
            PlanType.otHalfYear, 
            'Old Testament (1/2 Year)', 
            'Focus on the OT for 6 months.'
          ),
          _buildPlanTypeOption(
            PlanType.ntHalfYear, 
            'New Testament (1/2 Year)', 
            'Focus on the NT for 6 months.'
          ),

          if (_selectedType == PlanType.threeOldOneNew)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.infoContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'To complete this in one year, you will read three OT chapters on six days and one NT chapter on five days.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),

          // Custom books and Pace
          if (_selectedType == PlanType.sequential || _selectedType == PlanType.portions) ...[
            const Text('Books to Read'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showBookSelection,
              icon: const Icon(Icons.library_books),
              label: Text(_selectedBooks.length == ReferenceParser.allBooks.length 
                  ? 'All Books Selected' 
                  : '${_selectedBooks.length} Books Selected'),
            ),
            const SizedBox(height: 16),
            
            const Text('Chapters per day (Optional)'),
            const SizedBox(height: 8),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 3',
                border: OutlineInputBorder(),
                helperText: 'Leave empty to calculate based on duration',
              ),
              onChanged: (val) {
                setState(() {
                  _customChaptersPerDay = int.tryParse(val);
                });
              },
            ),
            const SizedBox(height: 16),
          ],

          // Duration (for sequential/portions)
          if (_selectedType == PlanType.sequential || _selectedType == PlanType.portions) ...[
            const Text('Duration'),
            Row(
              children: [
                _choiceChip('1 Year', _years == 1, () => setState(() => _years = 1)),
                const SizedBox(width: 8),
                _choiceChip('2 Years', _years == 2, () => setState(() => _years = 2)),
                const SizedBox(width: 8),
                _choiceChip('Custom End Date', _endDate != null, () => _selectDate(context, false)),
              ],
            ),
            if (_endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Ends on: ${_endDate!.month}/${_endDate!.day}/${_endDate!.year}', 
                  style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 16),
          ],

          // Reading Days
          const Text('Days of the week to read'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 1; i <= 7; i++)
                _dayCircle(i),
            ],
          ),
          const SizedBox(height: 16),

          // Start Date
          const Text('Start Date'),
          InkWell(
            onTap: () => _selectDate(context, true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_startDate.month}/${_startDate.day}/${_startDate.year}'),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _isCreating ? null : _createPlan,
              child: _isCreating 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Create & Start Plan'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPlanTypeOption(PlanType type, String title, String subtitle) {
    final isSelected = _selectedType == type;
    final colorScheme = Theme.of(context).colorScheme;

    return RadioListTile<PlanType>(
      value: type,
      groupValue: _selectedType,
      onChanged: (val) => setState(() => _selectedType = val!),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
      activeColor: colorScheme.primary,
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }

  Widget _dayCircle(int day) {
    final isSelected = _readingDays.contains(day);
    final colorScheme = Theme.of(context).colorScheme;
    final dayNames = ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return GestureDetector(
      onTap: () => _toggleDay(day),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          border: Border.all(color: isSelected ? colorScheme.primary : colorScheme.outline),
        ),
        child: Center(
          child: Text(
            dayNames[day],
            style: TextStyle(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

extension on ColorScheme {
  Color get infoContainer => primaryContainer; // Placeholder
}
