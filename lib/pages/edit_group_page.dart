import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/reference_parser.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';

class EditGroupPage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const EditGroupPage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Reading Plan State
  final List<String> _selectedBooks = [];
  final TextEditingController _searchController = TextEditingController();

  // Timeline State
  late DateTime _startDate;
  DateTime? _endDate;
  bool _isDaily = true;
  late DateTime
      _originalStartDate; // To check if start date is manipulated (though disabled)

  // Settings State
  late bool _isPublic;

  // Members State
  List<GroupMemberProgressData> _members = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Load Schedule to determine plan
      final schedule =
          await widget.groupService.schedule(widget.group.id).first;

      if (schedule.isNotEmpty) {
        _startDate = schedule.first.date;
        _endDate = schedule.last.date;
        _originalStartDate = _startDate;

        // Infer books
        final books = <String>{};
        for (final s in schedule) {
          for (final chap in s.chapters) {
            final book = ReferenceParser.parseBook(chap);
            if (book != null) books.add(book);
          }
        }
        _selectedBooks.addAll(books);

        // Infer Frequency (check for missing weekends)
        // If we find missing weekends in a long enough schedule, assume Weekdays.
        // Or check if any weekend exists.
        bool hasWeekend = false;
        for (final s in schedule) {
          if (s.date.weekday == DateTime.saturday ||
              s.date.weekday == DateTime.sunday) {
            hasWeekend = true;
            break;
          }
        }
        _isDaily = hasWeekend;
        // Edge case: if the schedule is short and happens to be M-F, we might guess wrong.
        // But defaults to Daily is safer unless proven otherwise.
      } else {
        _startDate = DateTime.now();
        _originalStartDate = _startDate;
        _isDaily = true;
      }

      // Load Settings
      _isPublic = widget.group.isPublic;

      // Load Members
      // memberOverallCompletion gives us the list with avatars
      final members = await widget.groupService
          .memberOverallCompletion(widget.group.id)
          .first;
      _members = members;

      setState(() {
        _isLoading = false;
      });
    } catch (e, st) {
      if (mounted) {
        ErrorLogger.log(e, st);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load group data')),
        );
        Navigator.pop(context);
      }
    }
  }

  int get _totalChapters {
    int count = 0;
    for (final book in _selectedBooks) {
      count += ReferenceParser.chapterCount(book) ?? 0;
    }
    return count;
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

  Future<void> _selectEndDate() async {
    final firstDate = _startDate; // Can end on start date
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _saveChanges() async {
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

    setState(() => _isSaving = true);
    unawaited(widget.vibrationService.lightImpact());

    try {
      // 1. Generate New Schedule
      final newSchedule = ScheduleGenerator.generateSchedule(
        books: _selectedBooks,
        startDate: _startDate,
        endDate: _endDate!,
        isDaily: _isDaily,
      );

      // 2. Update Schedule
      // We overwrite. First clear old schedule if we want to be clean?
      // updateScheduleBatch overwrites by dateId.
      // If the new schedule is shorter than the old one, we need to delete the extra future days.
      // Or we can delete all future schedule entries first.
      // For now, let's just overwrite. Deleting old schedule entirely is risky for progress history.
      // A robust "Edit Plan" usually asks if you want to keep history.
      // Here we assume "Reschedule" from Start Date means "Overwrite".

      // Strategy: Delete all schedule entries for this group, then write new ones.
      // This ensures no stale days remain.
      // WARNING: This clears progress for days that are removed or changed?
      // GroupService.deleteGroup deletes everything.
      // We don't have "deleteAllSchedule".
      // We will loop through existing schedule and delete? That's slow.
      // For now, we will just use updateScheduleBatch. Stale days (e.g. if we shortened the plan) will remain.
      // Ideally, we should fetch existing schedule again, identify dates NOT in new schedule, and delete them.

      final currentSchedule =
          await widget.groupService.schedule(widget.group.id).first;
      final newDateKeys = newSchedule
          .map((s) => '${s.date.year}-${s.date.month}-${s.date.day}')
          .toSet();

      // Find dates to delete (dates in current but not in new)
      for (final s in currentSchedule) {
        final key = '${s.date.year}-${s.date.month}-${s.date.day}';
        if (!newDateKeys.contains(key)) {
          await widget.groupService
              .deleteSchedule(groupId: widget.group.id, date: s.date);
        }
      }

      await widget.groupService.updateScheduleBatch(
        groupId: widget.group.id,
        schedules: newSchedule,
      );

      // 3. Update Settings
      if (_isPublic != widget.group.isPublic) {
        await widget.groupService.updateGroupPublicStatus(
          groupId: widget.group.id,
          isPublic: _isPublic,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group plan updated')),
        );
        Navigator.pop(context);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update plan')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _archiveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Group'),
        content: const Text(
          'Are you sure you want to archive (delete) this group? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.deleteGroup(
          groupId: widget.group.id,
          ownerUid: widget.auth.currentUser!.uid,
        );
        if (mounted) {
          // Go back twice (Edit -> Detail -> List)
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to archive group')),
          );
        }
      }
    }
  }

  Future<void> _kickMember(String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $name from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.kickMember(
          groupId: widget.group.id,
          uid: uid,
        );
        // Refresh list locally or rely on setState if stream updates
        // Since we loaded members once in initState via .first, we should remove locally
        setState(() {
          _members.removeWhere((m) => m.uid == uid);
        });
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove member')),
          );
        }
      }
    }
  }

  void _copyLink() {
    // For now, we simulate a link copy since we don't have deep linking set up yet.
    // Or maybe we do, but the prompt implies simple "Copy Link".
    // We'll copy the Group ID or a dummy link.
    Clipboard.setData(ClipboardData(text: 'Join my group: ${widget.group.id}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = widget.auth.currentUser;
    final isOwner = user?.uid == widget.group.ownerUid;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Edit Group Plan'),
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
                    // --- Reading Plan ---
                    Text(
                      'Reading Plan',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Modify the books in your plan.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search
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
                      onSelected: _addBook,
                      fieldViewBuilder:
                          (context, controller, focusNode, onEditingComplete) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onEditingComplete: onEditingComplete,
                          decoration: InputDecoration(
                            hintText: 'Add another book...',
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
                                  maxHeight: 200, maxWidth: 300),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option =
                                      options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(option),
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

                    // Chips
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
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

                    // --- Timeline ---
                    Text(
                      'Timeline',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adjust your schedule dates.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Opacity(
                            opacity: 0.6,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Start',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                enabled:
                                    false, // Visual only, interaction blocked by not having onTap
                              ),
                              child: Text(
                                "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}",
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
                                : 'Select end date, current selection: ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                            child: InkWell(
                              onTap: _selectEndDate,
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
                                      ? 'Select Date'
                                      : "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}",
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text('Frequency',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
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
                        onChanged: (val) => setState(() => _isDaily = val!),
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
                        onChanged: (val) => setState(() => _isDaily = val!),
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

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),

                    // --- Members ---
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
                              'Manage group participants.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: _copyLink,
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Copy Link'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_members.isEmpty)
                      const Text('No members loaded')
                    else
                      ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: _members.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final member = _members[index];
                          final isMe = member.uid == user?.uid;
                          final isMemberOwner =
                              member.uid == widget.group.ownerUid;
                          // In our simplified logic, owner is admin.
                          final role = isMemberOwner ? 'Group Owner' : 'Member';

                          return Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withOpacity(0.5)),
                              borderRadius:
                                  BorderRadius.circular(50), // pill shape
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      colorScheme.tertiaryContainer,
                                  backgroundImage: member.photoUrl != null
                                      ? CachedNetworkImageProvider(
                                          member.photoUrl!)
                                      : null,
                                  child: member.photoUrl == null
                                      ? Text(
                                          member.name.isNotEmpty
                                              ? member.name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                              color: colorScheme
                                                  .onTertiaryContainer),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(member.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w500)),
                                      Text(role,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme
                                                  .onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                if (isOwner && !isMe)
                                  IconButton(
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    color: colorScheme.onSurfaceVariant,
                                    tooltip: 'Remove ${member.name}',
                                    onPressed: () =>
                                        _kickMember(member.uid, member.name),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),

                    // --- Group Settings ---
                    Text(
                      'Group Settings',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visibility and archival options.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: const Text(
                          'Public Group',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'Visible in community search results',
                          style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant),
                        ),
                        value: _isPublic,
                        onChanged: (val) {
                          unawaited(widget.vibrationService.lightImpact());
                          setState(() => _isPublic = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (isOwner)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _archiveGroup,
                          icon: const Icon(Icons.inventory_2),
                          label: const Text('Archive Group'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(
                                color: colorScheme.error.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Save Button
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
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
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
