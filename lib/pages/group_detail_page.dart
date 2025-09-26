import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/group_members_section.dart';
import '../widgets/schedule_item_tile.dart';
import '../widgets/vibration_button.dart';
import '../services/vibration_service.dart';
import '../widgets/section_header.dart';
import '../services/reference_parser.dart';
import 'read_log_page.dart';

/// Page showing the members and schedule for a group.
class GroupDetailPage extends StatefulWidget {
  /// Group being displayed.
  final Group group;

  /// Service used for group operations.
  final GroupService groupService;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [GroupDetailPage].
  GroupDetailPage({
    super.key,
    required this.group,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  List<GroupSchedule>? _scheduleOverride;
  List<GroupSchedule>? _latestSchedule;
  late final TextEditingController _todayController;
  bool _isSavingToday = false;
  bool _editMode = false;

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _todayController = TextEditingController();
  }

  @override
  void dispose() {
    _todayController.dispose();
    super.dispose();
  }

  Future<void> _saveToday() async {
    if (_isSavingToday) return;
    final text = _todayController.text.trim();
    final chapters = ReferenceParser.normalizeList(
      text.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty),
    );
    if (chapters.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one chapter')),
      );
      return;
    }

    unawaited(widget.vibrationService.lightImpact());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final schedule = GroupSchedule(date: today, chapters: chapters);

    // Optimistic UI update
    final previous = _scheduleOverride ?? _latestSchedule;
    final updated = List<GroupSchedule>.from(previous ?? <GroupSchedule>[]);
    final idx = updated.indexWhere((s) => _dateKey(s.date) == _dateKey(today));
    if (idx >= 0) {
      updated[idx] = schedule;
    } else {
      updated.add(schedule);
    }
    updated.sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _isSavingToday = true;
        _scheduleOverride = updated;
      });
    }

    try {
      await widget.groupService
          .updateSchedule(groupId: widget.group.id, schedule: schedule);
      if (!mounted) return;
      setState(() {
        _isSavingToday = false;
        _scheduleOverride = null;
        _latestSchedule = updated;
      });
      _todayController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved today\'s reading')));
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to save today: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _isSavingToday = false;
        _scheduleOverride = previous;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to save')));
    }
  }

  Future<void> _deleteSchedule(GroupSchedule schedule) async {
    unawaited(widget.vibrationService.mediumImpact());
    final previous = _scheduleOverride ?? _latestSchedule;
    final updated = List<GroupSchedule>.from(previous ?? <GroupSchedule>[])
      ..removeWhere((s) => _dateKey(s.date) == _dateKey(schedule.date));
    if (mounted) {
      setState(() {
        _scheduleOverride = updated;
      });
    }
    try {
      await widget.groupService.deleteSchedule(
        groupId: widget.group.id,
        date: schedule.date,
      );
      if (mounted) {
        setState(() {
          _latestSchedule = updated;
          _scheduleOverride = null;
        });
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Entry deleted')));
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to delete schedule: $e');
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() {
          _scheduleOverride = previous;
        });
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Delete failed')));
      }
    }
  }

  Future<void> _toggleMyRead(bool read) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (read) {
        await ReadLogPage.writeReadLogEntry(
          user,
          firestore: widget.groupService.firestore,
          dateProvider: () => now,
        );
        await widget.groupService.firestore
            .collection('users')
            .doc(user.uid)
            .collection('reading')
            .doc(dateKey)
            .set({'read': true}, SetOptions(merge: true));
      } else {
        await widget.groupService.firestore
            .collection('read_logs')
            .doc(dateKey)
            .collection('entries')
            .doc(user.uid)
            .delete();
        await widget.groupService.firestore
            .collection('users')
            .doc(user.uid)
            .collection('reading')
            .doc(dateKey)
            .set({'read': false}, SetOptions(merge: true));
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle read: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update read status')));
    }
  }

  Future<void> _editSchedule([GroupSchedule? schedule]) async {
    final result = await Navigator.of(context).push<GroupSchedule>(
      animatedPageRoute(
        _EditScheduleDialog(
          schedule: schedule,
          vibrationService: widget.vibrationService,
        ),
      ),
    );

    if (result != null) {
      final previous = _scheduleOverride ?? _latestSchedule;
      final updated = List<GroupSchedule>.from(previous ?? <GroupSchedule>[]);
      if (schedule == null) {
        updated.add(result);
      } else {
        final index = updated.indexWhere((s) => s.date == schedule.date);
        if (index != -1) {
          updated[index] = result;
        } else {
          updated.add(result);
        }
      }
      updated.sort((a, b) => a.date.compareTo(b.date));
      if (mounted) {
        setState(() {
          _scheduleOverride = updated;
        });
      }
      final dateChanged = schedule != null && schedule.date != result.date;
      final newSchedule = List<GroupSchedule>.from(updated);

      unawaited(() async {
        try {
          if (dateChanged) {
            await widget.groupService.deleteSchedule(
              groupId: widget.group.id,
              date: schedule.date,
            );
          }
          await widget.groupService
              .updateSchedule(groupId: widget.group.id, schedule: result);
          if (mounted) {
            setState(() {
              _scheduleOverride = null;
              _latestSchedule = newSchedule;
            });
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Failed to update schedule: $e');
          }
          ErrorLogger.log(e, st);
          if (mounted) {
            setState(() {
              _scheduleOverride = previous;
            });
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update schedule')),
            );
          }
        }
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final userUid = user?.uid;
    final isOwner = userUid != null && userUid == widget.group.ownerUid;
    final memberStream = user != null
        ? widget.groupService.firestore
            .collection(GroupCollections.groups)
            .doc(widget.group.id)
            .collection(GroupCollections.members)
            .doc(user.uid)
            .snapshots()
        : null;

    // No predefined plans; manual entry only.

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberStream,
      builder: (context, membershipSnapshot) {
        final memberDoc = membershipSnapshot.data;
        final role = memberDoc?.data()?['role'] as String?;
        final isMember = isOwner || (memberDoc?.exists ?? false);
        final hasAdminPrivileges =
            isOwner || role == 'admin' || role == 'owner';
        final canManageRequests = hasAdminPrivileges && _editMode;
        final canEditSchedule = hasAdminPrivileges && _editMode;

        // Determine if a schedule for today already exists to control
        // whether the Save button/input should be enabled.
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final hasToday = (_scheduleOverride ?? _latestSchedule)
                ?.any((s) => _dateKey(s.date) == _dateKey(today)) ??
            false;

        return Scaffold(
          appBar: CommonStyles.buildAppBar(
            widget.group.name,
            actions: hasAdminPrivileges
                ? [
                    IconButton(
                      icon: Icon(_editMode ? Icons.check : Icons.edit),
                      tooltip: _editMode ? 'Done' : 'Edit',
                      onPressed: () {
                        setState(() {
                          _editMode = !_editMode;
                        });
                      },
                    )
                  ]
                : null,
          ),
          floatingActionButton: canEditSchedule
              ? FloatingActionButton(
                  heroTag: 'group-detail-fab',
                  onPressed: () {
                    unawaited(widget.vibrationService.lightImpact());
                    _editSchedule();
                  },
                  child: const Icon(Icons.add),
                )
              : null,
          body: Container(
            decoration: CommonStyles.backgroundGradient,
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                if (!isOwner && user != null && !isMember)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: widget.groupService.firestore
                        .collection(GroupCollections.groups)
                        .doc(widget.group.id)
                        .collection(GroupCollections.joinRequests)
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, reqSnapshot) {
                      final isPending = reqSnapshot.data?.exists ?? false;
                      if (isPending) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text('Join request pending'),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VibrationButton(
                            vibrationService: widget.vibrationService,
                            onPressed: () async {
                              try {
                                await widget.groupService.joinGroup(
                                  groupId: widget.group.id,
                                  uid: user.uid,
                                  name: user.displayName ?? '',
                                );
                                if (!mounted) return;
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Join request sent'),
                                  ),
                                );
                              } catch (e, st) {
                                if (kDebugMode) {
                                  debugPrint('Failed to join group: $e');
                                }
                                ErrorLogger.log(e, st);
                                if (!mounted) return;
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to join group'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Join Group'),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                if (canManageRequests) ...[
                  const SectionHeader('Join Requests'),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.groupService.firestore
                        .collection(GroupCollections.groups)
                        .doc(widget.group.id)
                        .collection(GroupCollections.joinRequests)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text('Failed to load join requests');
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final requests = snapshot.data!.docs;
                      if (requests.isEmpty) {
                        return const Text('No pending requests');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pending requests: ${requests.length}',
                            style: AppTextStyles.body,
                          ),
                          const SizedBox(height: 8),
                          ...requests.map((d) {
                            final data = d.data();
                            final uid = data['uid'] as String? ?? d.id;
                            final name = data['name'] as String? ?? '';
                            return ListTile(
                              title: Text(name.isEmpty ? uid : name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: () async {
                                      try {
                                        await widget.groupService
                                            .approveJoinRequest(
                                          groupId: widget.group.id,
                                          uid: uid,
                                        );
                                        if (!mounted) return;
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Request approved'),
                                          ),
                                        );
                                      } catch (e, st) {
                                        if (kDebugMode) {
                                          debugPrint(
                                              'Failed to approve request: $e');
                                        }
                                        ErrorLogger.log(e, st);
                                        if (!mounted) return;
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Failed to approve request'),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () async {
                                      try {
                                        await widget.groupService
                                            .denyJoinRequest(
                                          groupId: widget.group.id,
                                          uid: uid,
                                        );
                                        if (!mounted) return;
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Request denied'),
                                          ),
                                        );
                                      } catch (e, st) {
                                        if (kDebugMode) {
                                          debugPrint(
                                              'Failed to deny request: $e');
                                        }
                                        ErrorLogger.log(e, st);
                                        if (!mounted) return;
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('Failed to deny request'),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                ],
                GroupMembersSection(
                  membersStream: widget.groupService
                      .memberDailyCompletion(widget.group.id, includeUid: userUid),
                  currentUid: userUid,
                  onToggleCurrentUserRead: (read) => _toggleMyRead(read),
                ),
                const SectionHeader('Schedule'),
                if (canEditSchedule) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('today-chapters-field'),
                          controller: _todayController,
                          decoration: const InputDecoration(
                            labelText: "Today's chapters (comma separated)",
                            border: OutlineInputBorder(),
                          ),
                          enabled: !hasToday && !_isSavingToday,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          key: const Key('save-today-button'),
                          onPressed:
                              (_isSavingToday || hasToday) ? null : _saveToday,
                          child: _isSavingToday
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                StreamBuilder<List<GroupSchedule>>(
                  stream: widget.groupService.schedule(widget.group.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Failed to load schedule');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final fetched = List<GroupSchedule>.from(snapshot.data!)
                      ..sort((a, b) => a.date.compareTo(b.date));
                    _latestSchedule = fetched;
                    final schedule = _scheduleOverride ?? _latestSchedule!;
                    if (schedule.isEmpty) {
                      return const Text('No schedule');
                    }
                    final user = widget.auth.currentUser;
                    if (user == null) {
                      return Column(
                        children: schedule
                            .map(
                              (s) => ScheduleItemTile(
                                schedule: s,
                                onEdit: canEditSchedule
                                    ? () => _editSchedule(s)
                                    : null,
                                onDelete: canEditSchedule
                                    ? () => _deleteSchedule(s)
                                    : null,
                              ),
                            )
                            .toList(),
                      );
                    }

                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final dateKey =
                        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                    final readDoc = widget.groupService.firestore
                        .collection('read_logs')
                        .doc(dateKey)
                        .collection('entries')
                        .doc(user.uid)
                        .snapshots();

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: readDoc,
                      builder: (context, readSnap) {
                        final myRead = readSnap.data?.exists ?? false;
                        return Column(
                          children: schedule
                              .map(
                                (s) {
                                  final isToday = _dateKey(s.date) == _dateKey(today);
                                  return ScheduleItemTile(
                                    schedule: s,
                                    onEdit: canEditSchedule
                                        ? () => _editSchedule(s)
                                        : null,
                                    onDelete: canEditSchedule
                                        ? () => _deleteSchedule(s)
                                        : null,
                                    currentUserRead: isToday ? myRead : null,
                                    onToggleRead: isToday ? (v) => _toggleMyRead(v) : null,
                                  );
                                },
                              )
                              .toList(),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditScheduleDialog extends StatefulWidget {
  const _EditScheduleDialog({
    this.schedule,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  final GroupSchedule? schedule;
  final VibrationService vibrationService;

  @override
  State<_EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<_EditScheduleDialog> {
  late DateTime _selected;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _selected = widget.schedule?.date ?? DateTime.now();
    _controller = TextEditingController(
      text: widget.schedule?.chapters.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selected = picked;
      });
    }
  }

  void _save() {
    final chapters = ReferenceParser.normalizeList(
      _controller.text
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty),
    );
    Navigator.of(context)
        .pop(GroupSchedule(date: _selected, chapters: chapters));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.schedule == null ? 'Add Schedule' : 'Edit Schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Chapters (comma separated)',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pickDate,
            child: Text(_selected.toIso8601String().split('T').first),
          ),
        ],
      ),
      actions: [
        VibrationButton(
          vibrationService: widget.vibrationService,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        VibrationButton(
          vibrationService: widget.vibrationService,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
