import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
      final schedule =
          await widget.groupService.schedule(widget.group.id).first;

      if (schedule.isNotEmpty) {
        _startDate = schedule.first.date;
        _endDate = schedule.last.date;

        final books = <String>{};
        for (final s in schedule) {
          for (final chap in s.chapters) {
            final book = ReferenceParser.parseBook(chap);
            if (book != null) books.add(book);
          }
        }
        _selectedBooks.addAll(books);

        bool hasWeekend = false;
        for (final s in schedule) {
          if (s.date.weekday == DateTime.saturday ||
              s.date.weekday == DateTime.sunday) {
            hasWeekend = true;
            break;
          }
        }
        _isDaily = hasWeekend;
      } else {
        _startDate = DateTime.now();

        _isDaily = true;
      }

      _isPublic = widget.group.isPublic;

      final members = await widget.groupService
          .memberOverallCompletion(widget.group.id)
          .first;
      _members = members;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
    final firstDate = _startDate;
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
      final newSchedule = ScheduleGenerator.generateSchedule(
        books: _selectedBooks,
        startDate: _startDate,
        endDate: _endDate!,
        isDaily: _isDaily,
      );

      final currentSchedule =
          await widget.groupService.schedule(widget.group.id).first;
      final newDateKeys = newSchedule
          .map((s) => '${s.date.year}-${s.date.month}-${s.date.day}')
          .toSet();

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
    final textTheme = GoogleFonts.interTextTheme(theme.textTheme);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Content
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                    child: SizedBox(height: 80)), // Space for header
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildReadingPlanSection(colorScheme, textTheme),
                      const SizedBox(height: 24),
                      Divider(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 24),
                      _buildTimelineSection(colorScheme, textTheme),
                      const SizedBox(height: 24),
                      Divider(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 24),
                      _buildMembersSection(colorScheme, textTheme),
                      const SizedBox(height: 24),
                      Divider(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 24),
                      _buildGroupSettingsSection(colorScheme, textTheme),
                      const SizedBox(height: 100), // Space for bottom button
                    ]),
                  ),
                ),
              ],
            ),
          ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(context, colorScheme, textTheme),
          ),

          // Bottom Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildSaveButton(colorScheme, textTheme),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                        right: 48.0), // Balance back button
                    child: Text(
                      'Edit Group Plan',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingPlanSection(
      ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Subtitle
        Text(
          'Reading Plan',
          style: textTheme.headlineMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Modify the books in your plan.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),

        // Search Input
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
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Add another book...',
                hintStyle: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: colorScheme.onSurfaceVariant,
                ),
                suffixIcon: Icon(
                  Icons.arrow_drop_down,
                  color: colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.surfaceContainerHighest,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 200, maxWidth: 300),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            option,
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface,
                            ),
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
        if (_selectedBooks.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _selectedBooks.map((book) {
              return Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.book,
                      size: 18,
                      color: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      book,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _removeBook(book),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        if (_selectedBooks.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Info Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'This selection contains approximately ',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: '$_totalChapters chapters',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
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
      ],
    );
  }

  Widget _buildTimelineSection(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Subtitle
        Text(
          'Timeline',
          style: textTheme.headlineMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Adjust your schedule dates.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            // Start Date
            Expanded(
              child: Opacity(
                opacity: 0.6,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Start',
                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    enabled: false, // Visual only
                  ),
                  child: Text(
                    "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}",
                    style: textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // End Date
            Expanded(
              child: Semantics(
                button: true,
                label: _endDate == null
                    ? 'Select end date'
                    : 'Select end date, current selection: ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                child: InkWell(
                  onTap: _selectEndDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'End',
                      labelStyle: TextStyle(color: colorScheme.primary),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: colorScheme.primary, width: 2),
                      ),
                      suffixIcon: Icon(Icons.calendar_today,
                          color: colorScheme.onSurfaceVariant),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    child: Text(
                      _endDate == null
                          ? 'Select Date'
                          : "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}",
                      style: textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Frequency
        Text(
          'Frequency',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),

        // Frequency Cards
        _buildFrequencyCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Daily',
          subtitle: 'Every single day',
          icon: Icons.calendar_view_day,
          isSelected: _isDaily,
          onTap: () => setState(() => _isDaily = true),
        ),
        const SizedBox(height: 12),
        _buildFrequencyCard(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Weekdays',
          subtitle: 'Mon - Fri only',
          icon: Icons.date_range,
          isSelected: !_isDaily,
          onTap: () => setState(() => _isDaily = false),
        ),
      ],
    );
  }

  Widget _buildFrequencyCard({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final borderColor = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.2)
        : null; // Adjusted opacity
    final iconColor =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Radio Indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  width: 2,
                ),
                color: isSelected ? colorScheme.primary : null,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersSection(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Members',
                  style: textTheme.headlineMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage group participants.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: const StadiumBorder(),
                textStyle: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No members loaded',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final member = _members[index];
              final isMe = member.uid == widget.auth.currentUser?.uid;
              final isMemberOwner = member.uid == widget.group.ownerUid;
              final role = isMemberOwner ? 'Group Admin' : 'Member';
              final isOwner =
                  widget.group.ownerUid == widget.auth.currentUser?.uid;

              return Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(50), // Pill shape
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isMemberOwner
                          ? colorScheme.tertiaryContainer
                          : colorScheme.secondaryContainer,
                      backgroundImage: member.photoUrl != null
                          ? CachedNetworkImageProvider(member.photoUrl!)
                          : null,
                      child: member.photoUrl == null
                          ? Text(
                              member.name.isNotEmpty
                                  ? member.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: isMemberOwner
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            role,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isOwner && !isMe)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: colorScheme.onSurfaceVariant,
                        tooltip: 'Remove member',
                        onPressed: () => _kickMember(member.uid, member.name),
                      ),
                    if (isMe) ...[
                      // Maybe show something for yourself? or nothing.
                    ]
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGroupSettingsSection(
      ColorScheme colorScheme, TextTheme textTheme) {
    final isOwner = widget.auth.currentUser?.uid == widget.group.ownerUid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Group Settings',
          style: textTheme.headlineMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Visibility and archival options.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),

        // Public Group Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Public Group',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visible in community search results',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isPublic,
                activeTrackColor: colorScheme.primary,
                onChanged: (val) => setState(() => _isPublic = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (isOwner)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _archiveGroup,
              icon: Icon(Icons.inventory_2, color: colorScheme.tertiary),
              label: Text('Archive Group',
                  style: TextStyle(color: colorScheme.tertiary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: colorScheme.tertiary.withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
        height: 56,
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
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}
