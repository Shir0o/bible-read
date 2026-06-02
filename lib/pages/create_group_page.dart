import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../models/schedule_mode.dart';
import '../services/group_service.dart';
import '../services/reference_parser.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import 'group_detail_page.dart';

class CreateGroupPage extends StatefulWidget {
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  CreateGroupPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final List<String> _selectedBooks = [];
  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime? _endDate;
  List<int> _selectedWeekdays = [1, 2, 3, 4, 5, 6, 7]; // Mon-Sun
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _chaptersController = TextEditingController(
    text: '3',
  );
  ScheduleMode _scheduleMode = ScheduleMode.endDate;
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
    _chaptersController.dispose();
    super.dispose();
  }

  int get _totalChapters {
    int count = 0;
    for (final book in _selectedBooks) {
      count += ReferenceParser.chapterCount(book) ?? 0;
    }
    return count;
  }

  double get _pace {
    if (_scheduleMode == ScheduleMode.chaptersPerDay) {
      return double.tryParse(_chaptersController.text) ?? 0;
    }
    if (_endDate == null || _totalChapters == 0 || _selectedWeekdays.isEmpty) {
      return 0;
    }
    int days = 0;
    DateTime current = _startDate;
    // Simple day counting based on frequency
    while (!current.isAfter(_endDate!)) {
      if (_selectedWeekdays.contains(current.weekday)) {
        days++;
      }
      current = current.add(const Duration(days: 1));
    }
    if (days == 0) return 0;
    return _totalChapters / days;
  }

  DateTime? get _estimatedEndDate {
    if (_scheduleMode == ScheduleMode.endDate) return _endDate;
    final pace = double.tryParse(_chaptersController.text) ?? 0;
    if (pace <= 0 || _totalChapters == 0 || _selectedWeekdays.isEmpty) {
      return null;
    }

    int daysNeeded = (_totalChapters / pace).ceil();
    DateTime current = _startDate;
    int daysFound = 0;
    int safetyLimit = 365 * 20;

    while (daysFound < daysNeeded && safetyLimit > 0) {
      safetyLimit--;
      if (_selectedWeekdays.contains(current.weekday)) {
        daysFound++;
        if (daysFound == daysNeeded) return current;
      }
      current = current.add(const Duration(days: 1));
    }
    return null;
  }

  void _addBook(String book) {
    if (!_selectedBooks.contains(book)) {
      setState(() {
        _selectedBooks.add(book);
        _searchController.clear();
      });
    }
  }

  void _removeBook(String book) {
    setState(() {
      _selectedBooks.remove(book);
    });
  }

  void _toggleDay(int day, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectedWeekdays.contains(day)) {
          _selectedWeekdays.add(day);
          _selectedWeekdays.sort();
        }
      } else {
        _selectedWeekdays.remove(day);
      }
    });
  }

  Future<void> _selectDate(bool isStart) async {
    unawaited(widget.vibrationService.lightImpact());
    final initialDate = isStart ? _startDate : (_endDate ?? _startDate);
    final firstDate = isStart
        ? DateTime.now().subtract(const Duration(days: 365))
        : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _createSchedule() async {
    if (_selectedBooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one book.')),
      );
      return;
    }

    int? fixedChapters;
    if (_scheduleMode == ScheduleMode.chaptersPerDay) {
      fixedChapters = int.tryParse(_chaptersController.text);
      if (fixedChapters == null || fixedChapters <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid number of chapters per day.'),
          ),
        );
        return;
      }
    } else {
      if (_endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an end date.')),
        );
        return;
      }
    }

    final user = widget.auth.currentUser;
    if (user == null) return;

    setState(() => _isCreating = true);

    try {
      // 1. Create Group
      // Generate a name like "Genesis, Exodus Plan"
      String name = 'Reading Plan';
      if (_selectedBooks.isNotEmpty) {
        if (_selectedBooks.length <= 2) {
          name = "${_selectedBooks.join(', ')} Plan";
        } else {
          name = "${_selectedBooks.take(2).join(', ')} & more Plan";
        }
      }

      final groupId = await widget.groupService.createGroup(
        ownerUid: user.uid,
        name: name,
      );

      // 2. Generate Schedule
      final scheduleList = ScheduleGenerator.generateSchedule(
        books: _selectedBooks,
        startDate: _startDate,
        endDate: _endDate,
        fixedChaptersPerDay: fixedChapters,
        selectedWeekdays: _selectedWeekdays,
      );

      // 3. Upload Schedule
      await widget.groupService.updateScheduleBatch(
        groupId: groupId,
        schedules: scheduleList,
      );

      if (!mounted) return;

      // 4. Navigate to Group
      // We push replacement so the user can't "back" into the create page
      final group = Group(
        id: groupId,
        name: name,
        ownerUid: user.uid,
        memberCount: 1,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GroupDetailPage(
            group: group,
            groupService: widget.groupService,
            auth: widget.auth,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create group: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('New Group Plan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reading Plan Section
                    Text(
                      'Reading Plan',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Select the books you'll be reading together.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search Box
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return ReferenceParser.allBooks.where((String option) {
                          return option.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              );
                        });
                      },
                      onSelected: (String selection) {
                        _addBook(selection);
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onEditingComplete) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onEditingComplete: onEditingComplete,
                          decoration: InputDecoration(
                            hintText: 'Search for a book...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 200,
                                maxWidth: 300,
                              ), // Approximate width
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(
                                    index,
                                  );
                                  return InkWell(
                                    onTap: () {
                                      unawaited(
                                        widget.vibrationService.lightImpact(),
                                      );
                                      onSelected(option);
                                    },
                                    child: Semantics(
                                      button: true,
                                      label: 'Add $option',
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Text(option),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Selected Books Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedBooks.map((book) {
                        return InputChip(
                          label: Text(book),
                          selected: true,
                          selectedColor: colorScheme.primary,
                          labelStyle: TextStyle(color: colorScheme.onPrimary),
                          onDeleted: () => _removeBook(book),
                          deleteIconColor: colorScheme.onPrimary.withValues(
                            alpha: 0.8,
                          ),
                          checkmarkColor: colorScheme.onPrimary,
                        );
                      }).toList(),
                    ),
                    if (_selectedBooks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text:
                                      'This selection contains approximately ',
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$_totalChapters chapters',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),

                    // Timeline Section
                    Text(
                      'Timeline',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set your schedule mode and dates.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Schedule Mode Selection
                    Center(
                      child: SegmentedButton<ScheduleMode>(
                        segments: const [
                          ButtonSegment(
                            value: ScheduleMode.endDate,
                            label: Text('By End Date'),
                            icon: Icon(Icons.event),
                          ),
                          ButtonSegment(
                            value: ScheduleMode.chaptersPerDay,
                            label: Text('By Chapters / Day'),
                            icon: Icon(Icons.auto_stories),
                          ),
                        ],
                        selected: {_scheduleMode},
                        onSelectionChanged: (Set<ScheduleMode> newSelection) {
                          unawaited(widget.vibrationService.lightImpact());
                          setState(() {
                            _scheduleMode = newSelection.first;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Semantics(
                            button: true,
                            label:
                                'Select start date, current selection: ${_startDate.month}/${_startDate.day}/${_startDate.year}',
                            child: InkWell(
                              onTap: () => _selectDate(true),
                              borderRadius: BorderRadius.circular(16),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Start Date',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  suffixIcon: const Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  '${_startDate.month}/${_startDate.day}/${_startDate.year}',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (_scheduleMode == ScheduleMode.endDate)
                          Expanded(
                            child: Semantics(
                              button: true,
                              label: _endDate == null
                                  ? 'Select end date'
                                  : 'Select end date, current selection: ${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                              child: InkWell(
                                onTap: () => _selectDate(false),
                                borderRadius: BorderRadius.circular(16),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'End Date',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    suffixIcon: const Icon(
                                      Icons.calendar_today,
                                    ),
                                  ),
                                  child: Text(
                                    _endDate == null
                                        ? 'mm/dd/yyyy'
                                        : '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: TextField(
                              controller: _chaptersController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Chapters / Day',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                prefixIcon: const Icon(Icons.auto_stories),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  // Trigger estimated end date recalculation
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Frequency',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Quick Presets
                    Row(
                      children: [
                        ActionChip(
                          label: const Text('Daily'),
                          onPressed: () {
                            unawaited(widget.vibrationService.lightImpact());
                            setState(() {
                              _selectedWeekdays = [1, 2, 3, 4, 5, 6, 7];
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          label: const Text('Weekdays'),
                          onPressed: () {
                            unawaited(widget.vibrationService.lightImpact());
                            setState(() {
                              _selectedWeekdays = [1, 2, 3, 4, 5];
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Individual Day Selection
                    Wrap(
                      spacing: 4,
                      children: [
                        _DayChip(
                          label: 'M',
                          dayValue: 1,
                          isSelected: _selectedWeekdays.contains(1),
                          onToggle: (selected) => _toggleDay(1, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'T',
                          dayValue: 2,
                          isSelected: _selectedWeekdays.contains(2),
                          onToggle: (selected) => _toggleDay(2, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'W',
                          dayValue: 3,
                          isSelected: _selectedWeekdays.contains(3),
                          onToggle: (selected) => _toggleDay(3, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'T',
                          dayValue: 4,
                          isSelected: _selectedWeekdays.contains(4),
                          onToggle: (selected) => _toggleDay(4, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'F',
                          dayValue: 5,
                          isSelected: _selectedWeekdays.contains(5),
                          onToggle: (selected) => _toggleDay(5, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'S',
                          dayValue: 6,
                          isSelected: _selectedWeekdays.contains(6),
                          onToggle: (selected) => _toggleDay(6, selected),
                          vibrationService: widget.vibrationService,
                        ),
                        _DayChip(
                          label: 'S',
                          dayValue: 7,
                          isSelected: _selectedWeekdays.contains(7),
                          onToggle: (selected) => _toggleDay(7, selected),
                          vibrationService: widget.vibrationService,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_scheduleMode == ScheduleMode.endDate &&
                        _endDate != null)
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Pace: ~${_pace.toStringAsFixed(1)} chapters / day',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    if (_scheduleMode == ScheduleMode.chaptersPerDay &&
                        _estimatedEndDate != null)
                      Row(
                        children: [
                          Icon(
                            Icons.event_note,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Estimated End Date: ${_estimatedEndDate!.month}/${_estimatedEndDate!.day}/${_estimatedEndDate!.year}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),

                    // Members Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Members',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Invite your reading group.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Link copied to clipboard (simulation)',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Copy Link'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        hintText: 'Find people...',
                        prefixIcon: const Icon(Icons.person_search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Placeholder Invite Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.contact_page),
                        label: const Text('Invite from Contacts'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Create Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    colorScheme.surface,
                    colorScheme.surface.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isCreating
                      ? null
                      : () {
                          unawaited(widget.vibrationService.mediumImpact());
                          _createSchedule();
                        },
                  icon: _isCreating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isCreating ? 'Creating...' : 'Create Schedule'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final int dayValue;
  final bool isSelected;
  final Function(bool) onToggle;
  final VibrationService vibrationService;

  const _DayChip({
    required this.label,
    required this.dayValue,
    required this.isSelected,
    required this.onToggle,
    required this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        unawaited(vibrationService.lightImpact());
        onToggle(selected);
      },
      selectedColor: colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: const CircleBorder(),
    );
  }
}
