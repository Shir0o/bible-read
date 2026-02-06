import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
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
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isDaily = true; // true = Daily, false = Weekdays
  final TextEditingController _searchController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
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
    if (_endDate == null || _totalChapters == 0) return 0;
    int days = 0;
    DateTime current = _startDate;
    // Simple day counting based on frequency
    while (!current.isAfter(_endDate!)) {
      if (_isDaily || (current.weekday >= 1 && current.weekday <= 5)) {
        days++;
      }
      current = current.add(const Duration(days: 1));
    }
    if (days == 0) return 0;
    return _totalChapters / days;
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
    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an end date.')),
      );
      return;
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
        endDate: _endDate!,
        isDaily: _isDaily,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
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
                          return option
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase());
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
                                  maxWidth: 300), // Approximate width
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option =
                                      options.elementAt(index);
                                  return InkWell(
                                    onTap: () {
                                      unawaited(widget.vibrationService
                                          .lightImpact());
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
                          deleteIconColor:
                              colorScheme.onPrimary.withOpacity(0.8),
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
                            Icon(Icons.info_outline,
                                color: colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text:
                                      'This selection contains approximately ',
                                  style:
                                      TextStyle(color: colorScheme.onSurface),
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
                      'Set your start and end dates.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
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
                                  labelText: 'Start',
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
                                  labelText: 'End',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  suffixIcon: const Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _endDate == null
                                      ? 'mm/dd/yyyy'
                                      : '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Frequency',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    // Frequency Options
                    Container(
                      decoration: BoxDecoration(
                        border: _isDaily
                            ? Border.all(color: colorScheme.primary)
                            : Border.all(
                                color: colorScheme.outline.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                        color: _isDaily
                            ? colorScheme.primaryContainer.withOpacity(0.4)
                            : null,
                      ),
                      child: RadioListTile<bool>(
                        value: true,
                        groupValue: _isDaily,
                        onChanged: (val) {
                          unawaited(widget.vibrationService.lightImpact());
                          setState(() => _isDaily = val!);
                        },
                        title: const Text('Daily'),
                        subtitle: const Text('Every single day'),
                        secondary: Icon(Icons.calendar_view_day,
                            color: _isDaily
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: !_isDaily
                            ? Border.all(color: colorScheme.primary)
                            : Border.all(
                                color: colorScheme.outline.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                        color: !_isDaily
                            ? colorScheme.primaryContainer.withOpacity(0.4)
                            : null,
                      ),
                      child: RadioListTile<bool>(
                        value: false,
                        groupValue: _isDaily,
                        onChanged: (val) {
                          unawaited(widget.vibrationService.lightImpact());
                          setState(() => _isDaily = val!);
                        },
                        title: const Text('Weekdays'),
                        subtitle: const Text('Mon - Fri only'),
                        secondary: Icon(Icons.date_range,
                            color: !_isDaily
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_endDate != null)
                      Row(
                        children: [
                          Icon(Icons.speed,
                              size: 16, color: colorScheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            'Pace: ~${_pace.toStringAsFixed(1)} chapters / day',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colorScheme.secondary),
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
                                      'Link copied to clipboard (simulation)')),
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
                            borderRadius: BorderRadius.circular(30)),
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
                    colorScheme.surface.withOpacity(0.0),
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
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: Text(_isCreating ? 'Creating...' : 'Create Schedule'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
