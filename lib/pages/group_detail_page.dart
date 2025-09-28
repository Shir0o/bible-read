import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../models/schedule_template.dart';
import '../widgets/common_styles.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/group_members_section.dart';
import '../widgets/schedule_item_tile.dart';
import '../widgets/vibration_button.dart';
import '../services/vibration_service.dart';
import '../widgets/section_header.dart';
import '../services/reference_parser.dart';
import 'read_log_page.dart';
import 'group_join_requests_page.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/schedule_template.dart';

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
  late final TextEditingController _nameController;
  late DateTime _progressDate;
  bool _isSavingToday = false;
  bool _editMode = false;
  bool _isSavingName = false;
  late String _groupName;
  // Automation Plans UI (consolidated): handled via list + dialogs.

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _todayController = TextEditingController();
    _groupName = widget.group.name;
    _nameController = TextEditingController(text: _groupName);
    final now = DateTime.now();
    _progressDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _todayController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveToday() async {
    if (_isSavingToday) return;
    final text = _todayController.text.trim();
    final chapters = ReferenceParser.parseChaptersList(text);
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

  Future<void> _saveGroupName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _groupName || _isSavingName) return;
    setState(() => _isSavingName = true);
    try {
      await widget.groupService
          .updateGroupName(groupId: widget.group.id, name: newName);
      if (!mounted) return;
      setState(() {
        _groupName = newName;
        _isSavingName = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group name updated')));
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to update group name: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() => _isSavingName = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to update name')));
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

  Future<void> _toggleMyReadForDate(DateTime date, bool read) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      final target = DateTime(date.year, date.month, date.day);
      final dateKey =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final db = widget.groupService.firestore;
      final progressDoc = db
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid);
      if (read) {
        await progressDoc.set({'done': true, 'ts': Timestamp.now()});
      } else {
        await progressDoc.delete();
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle read: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update read status')));
    }
  }

  Future<void> _toggleMyChapterForDate(
      DateTime date, int chapterIndex, bool read) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      final target = DateTime(date.year, date.month, date.day);
      final dateKey =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final db = widget.groupService.firestore;
      final base = db
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid);
      final itemDoc = base.collection('items').doc(chapterIndex.toString());
      final summaryDoc = db
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(user.uid);

      await db.runTransaction((tx) async {
        final itemSnap = await tx.get(itemDoc);
        final baseSnap = await tx.get(base);
        final nowTs = Timestamp.now();

        if (read) {
          if (itemSnap.exists) return; // already checked
          tx.set(itemDoc, {'done': true, 'ts': nowTs});
          final prevCount = (baseSnap.data()?['count'] as num?)?.toInt() ?? 0;
          final baseData = {
            'done': true,
            'ts': nowTs,
            'uid': user.uid,
            'groupId': widget.group.id,
            'dateId': dateKey,
            'count': prevCount + 1,
          };
          if (baseSnap.exists) {
            tx.update(base, baseData);
          } else {
            tx.set(base, baseData);
          }
          final summarySnap = await tx.get(summaryDoc);
          final prevCompleted =
              (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;
          tx.set(summaryDoc, {'completed': prevCompleted + 1},
              SetOptions(merge: true));
        } else {
          if (!itemSnap.exists) return; // already unchecked
          tx.delete(itemDoc);
          final prevCount = (baseSnap.data()?['count'] as num?)?.toInt() ?? 0;
          final newCount = prevCount > 0 ? prevCount - 1 : 0;
          if (baseSnap.exists) {
            if (newCount == 0) {
              tx.delete(base);
            } else {
              tx.update(base, {'count': newCount, 'ts': nowTs});
            }
          }
          final summarySnap = await tx.get(summaryDoc);
          final prevCompleted =
              (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;
          final newCompleted = prevCompleted > 0 ? prevCompleted - 1 : 0;
          tx.set(summaryDoc, {'completed': newCompleted}, SetOptions(merge: true));
        }
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle chapter: $e');
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
            _groupName,
            actions: hasAdminPrivileges
                ? [
                    // Join requests action for owners/admins.
                    IconButton(
                      icon: const Icon(Icons.group_add_outlined),
                      tooltip: 'Join requests',
                      onPressed: () {
                        unawaited(widget.vibrationService.lightImpact());
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupJoinRequestsPage(
                              groupId: widget.group.id,
                              groupService: widget.groupService,
                              auth: widget.auth,
                            ),
                          ),
                        );
                      },
                    ),
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
                if (_editMode && hasAdminPrivileges) ...[
                  const SectionHeader('Group'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('group-name-field'),
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Group name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          key: const Key('save-group-name-button'),
                          onPressed: _isSavingName ? null : _saveGroupName,
                          child: _isSavingName
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
                  const SizedBox(height: 16),
                  const SectionHeader('Auto Content Plans'),
                  StreamBuilder<List<(String, ScheduleTemplate)>>(
                    stream: widget.groupService
                        .scheduleTemplates(widget.group.id),
                    builder: (context, listSnap) {
                      final items = (listSnap.data ?? const []);
                      if (items.isEmpty) {
                        return const Text('No plans yet. Tap Add Plan to create one.');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...items.map((entry) {
                            final id = entry.$1;
                            final t = entry.$2;
                            final isDefault = id == 'default';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                (t.name?.isNotEmpty == true)
                                    ? t.name!
                                    : (isDefault ? 'Default Auto Plan' : 'Auto Plan $id'),
                              ),
                              subtitle: Text(
                                  '${t.plan ?? 'none'} · ${t.startTimeLocal} ${t.timezone}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit',
                                    onPressed: () async {
                                      final edited = await showDialog<ScheduleTemplate>(
                                        context: context,
                                        builder: (_) => _EditAutoTemplateDialog(initial: t),
                                      );
                                      if (edited != null) {
                                        try {
                                          await widget.groupService.updateScheduleTemplate(
                                            groupId: widget.group.id,
                                            templateId: id,
                                            template: edited,
                                          );
                                        } catch (e, st) {
                                          ErrorLogger.log(e, st);
                                        }
                                      }
                                    },
                                  ),
                                  Switch(
                                    value: t.active,
                                    onChanged: (v) async {
                                      try {
                                        await widget.groupService
                                            .updateScheduleTemplate(
                                          groupId: widget.group.id,
                                          templateId: id,
                                          template: t.copyWith(active: v),
                                        );
                                      } catch (e, st) {
                                        ErrorLogger.log(e, st);
                                      }
                                    },
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'reset') {
                                        try {
                                          await FirebaseFunctions.instanceFor(region: 'us-central1')
                                              .httpsCallable('resetPlanCursor')
                                              .call({
                                            'groupId': widget.group.id,
                                            'templateId': id,
                                            'cursorRef': (t.startRef ?? 'Gen 1'),
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Plan cursor reset')),
                                            );
                                          }
                                        } catch (e, st) {
                                          ErrorLogger.log(e, st);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Failed to reset plan')),
                                            );
                                          }
                                        }
                                      } else if (value == 'today') {
                                        try {
                                          await FirebaseFunctions.instanceFor(region: 'us-central1')
                                              .httpsCallable('materializeToday')
                                              .call({
                                            'groupId': widget.group.id,
                                            'templateId': id,
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Created/updated today\'s entry')),
                                            );
                                          }
                                        } catch (e, st) {
                                          ErrorLogger.log(e, st);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Failed to create today')),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'today', child: Text('Create Today Now')),
                                      PopupMenuItem(value: 'reset', child: Text('Reset Next to Start')),
                                    ],
                                  ),
                                  if (!isDefault)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Delete',
                                      onPressed: () async {
                                        try {
                                          await widget.groupService
                                              .deleteScheduleTemplate(
                                            groupId: widget.group.id,
                                            templateId: id,
                                          );
                                        } catch (e, st) {
                                          ErrorLogger.log(e, st);
                                        }
                                      },
                                    )
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Auto Plan'),
                      onPressed: () async {
                        final created = await showDialog<ScheduleTemplate>(
                          context: context,
                          builder: (_) => _EditAutoTemplateDialog(
                            initial: ScheduleTemplate.defaultUtc().copyWith(
                              plan: 'sequential_ot',
                              weekdays: const ['MO', 'TU', 'WE', 'TH', 'FR', 'SA'],
                              chaptersPerDay: 1,
                              name: 'New Auto Plan',
                            ),
                          ),
                        );
                        if (created != null) {
                          try {
                            await widget.groupService.createScheduleTemplate(
                              groupId: widget.group.id,
                              template: created,
                            );
                          } catch (e, st) {
                            ErrorLogger.log(e, st);
                          }
                        }
                      },
                    ),
                  ),
                ],
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
                // Join requests moved to a dedicated page via the app bar action.
                GroupMembersSection(
                  title: 'Members',
                  membersStream: widget.groupService.memberOverallCompletion(
                    widget.group.id,
                    includeUid: userUid,
                  ),
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
                    return Column(
                      children: schedule.asMap().entries.map((e) {
                        final index = e.key;
                        final s = e.value;
                        final baseTile = ScheduleItemTile(
                          schedule: s,
                          onEdit:
                              canEditSchedule ? () => _editSchedule(s) : null,
                          onDelete:
                              canEditSchedule ? () => _deleteSchedule(s) : null,
                          onTap: !canEditSchedule
                              ? () {
                                  setState(() {
                                    _progressDate = DateTime(
                                        s.date.year, s.date.month, s.date.day);
                                  });
                                }
                              : null,
                        );
                        if (user == null || canEditSchedule) {
                          return baseTile;
                        }
                        final dateKey = _dateKey(s.date);
                        final itemsStream = widget.groupService.firestore
                            .collection(GroupCollections.groups)
                            .doc(widget.group.id)
                            .collection('progress')
                            .doc(dateKey)
                            .collection('entries')
                            .doc(user.uid)
                            .collection('items')
                            .snapshots();
                        return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: itemsStream,
                          builder: (context, snap) {
                            final checked = <int>{};
                            for (final d in snap.data?.docs ?? const []) {
                              final idx = int.tryParse(d.id);
                              if (idx != null) checked.add(idx);
                            }
                            return ScheduleItemTile(
                              schedule: s,
                              onEdit: canEditSchedule
                                  ? () => _editSchedule(s)
                                  : null,
                              onDelete: canEditSchedule
                                  ? () => _deleteSchedule(s)
                                  : null,
                              checkedChapters: checked,
                              onToggleChapter: (chapterIndex, v) {
                                setState(() {
                                  _progressDate = DateTime(
                                      s.date.year, s.date.month, s.date.day);
                                });
                                _toggleMyChapterForDate(
                                    s.date, chapterIndex, v);
                              },
                              onTap: !canEditSchedule
                                  ? () {
                                      setState(() {
                                        _progressDate = DateTime(s.date.year,
                                            s.date.month, s.date.day);
                                      });
                                    }
                                  : null,
                            );
                          },
                        );
                      }).toList(),
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
    final chapters = ReferenceParser.parseChaptersList(_controller.text);
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

class _EditAutoTemplateDialog extends StatefulWidget {
  const _EditAutoTemplateDialog({this.initial});
  final ScheduleTemplate? initial;

  @override
  State<_EditAutoTemplateDialog> createState() => _EditAutoTemplateDialogState();
}

class _EditAutoTemplateDialogState extends State<_EditAutoTemplateDialog> {
  late bool _active;
  late String _timezone;
  late String _startTime;
  late String? _plan;
  late TextEditingController _name;
  late TextEditingController _chapters;
  late TextEditingController _startRef;
  late TextEditingController _tzCtl;
  late TextEditingController _timeCtl;
  Set<String> _weekdays = <String>{};

  @override
  void initState() {
    super.initState();
    final t = widget.initial ?? ScheduleTemplate.defaultUtc();
    _active = t.active;
    _timezone = t.timezone;
    _startTime = t.startTimeLocal;
    _plan = t.plan;
    _name = TextEditingController(text: t.name ?? '');
    _chapters = TextEditingController(
        text: t.chaptersPerDay == null ? '' : t.chaptersPerDay.toString());
    _startRef = TextEditingController(text: t.startRef ?? 'Gen 1');
    _weekdays = Set<String>.from(t.weekdays ?? const <String>[]);
    _tzCtl = TextEditingController(text: _timezone);
    _timeCtl = TextEditingController(text: _startTime);
  }

  @override
  void dispose() {
    _name.dispose();
    _chapters.dispose();
    _startRef.dispose();
    _tzCtl.dispose();
    _timeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Auto Plan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Timezone (IANA)',
              ),
              controller: _tzCtl,
              onChanged: (v) => _timezone = v.trim(),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Start time (HH:mm)'),
              controller: _timeCtl,
              onChanged: (v) => _startTime = v.trim(),
            ),
            const SizedBox(height: 8),
            CommonStyles.buildTappableCard(
              onTap: () => setState(() => _active = !_active),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
              ),
            ),
            DropdownButtonFormField<String>(
              value: _plan ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('None')),
                DropdownMenuItem(value: 'sequential_ot', child: Text('Sequential OT')),
              ],
              onChanged: (v) => setState(() => _plan = (v?.isEmpty ?? true) ? null : v),
              decoration: const InputDecoration(labelText: 'Plan'),
            ),
            if (_plan != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _chapters,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Chapters per day'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final code in const ['SU','MO','TU','WE','TH','FR','SA'])
                      FilterChip(
                        label: Text(code),
                        selected: _weekdays.contains(code),
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _weekdays.add(code);
                            } else {
                              _weekdays.remove(code);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _startRef,
                decoration: const InputDecoration(labelText: 'Start at (e.g., Gen 1)'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final t = ScheduleTemplate(
              active: _active,
              timezone: _timezone,
              startTimeLocal: _startTime,
              rrule: 'FREQ=DAILY;INTERVAL=1',
              plan: _plan,
              chaptersPerDay: int.tryParse(_chapters.text.trim()),
              weekdays: _plan == null ? null : _weekdays.toList(),
              startRef: _plan == null ? null : _startRef.text.trim(),
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            );
            Navigator.of(context).pop(t);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
