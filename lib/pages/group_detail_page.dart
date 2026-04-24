import 'dart:async';

import 'package:bible_read/widgets/group_members_list.dart';
import 'package:bible_read/widgets/group_progress_card.dart';
import 'package:bible_read/widgets/todays_reading_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/error_logger.dart';
import '../services/bible_progress_service.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/vibration_button.dart';
import 'edit_group_page.dart';
import 'group_join_requests_page.dart';
import 'invite_member_page.dart';
import 'group_catch_up_page.dart';

typedef GroupDatePicker = Future<DateTime?> Function({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
});

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

  /// Picker used to choose schedule dates.
  final GroupDatePicker datePicker;

  /// Aggregates completed chapters across joined groups.
  final BibleProgressService bibleProgressService;

  /// Service for friend operations.
  final FriendService friendService;

  /// Date to consider as "today" (for testing).
  final DateTime? currentDate;

  /// Creates a [GroupDetailPage].
  factory GroupDetailPage({
    Key? key,
    required Group group,
    GroupService? groupService,
    FriendService? friendService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
    GroupDatePicker? datePicker,
    BibleProgressService? bibleProgressService,
    DateTime? currentDate,
  }) {
    final resolvedGroupService = groupService ?? GroupService();
    final resolvedBibleProgressService = bibleProgressService ??
        BibleProgressService(
          firestore: resolvedGroupService.firestore,
          groupService: resolvedGroupService,
        );
    final resolvedFriendService = friendService ??
        FriendService(firestore: resolvedGroupService.firestore);

    return GroupDetailPage._(
      key: key,
      group: group,
      groupService: resolvedGroupService,
      friendService: resolvedFriendService,
      auth: auth ?? FirebaseAuth.instance,
      vibrationService: vibrationService ?? const VibrationService(),
      datePicker: datePicker ?? _defaultDatePicker,
      bibleProgressService: resolvedBibleProgressService,
      currentDate: currentDate,
    );
  }

  const GroupDetailPage._({
    super.key,
    required this.group,
    required this.groupService,
    required this.friendService,
    required this.auth,
    required this.vibrationService,
    required this.datePicker,
    required this.bibleProgressService,
    this.currentDate,
  });

  static Future<DateTime?> _defaultDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  late Stream<List<GroupSchedule>> _scheduleStream;
  final Map<String, bool> _pendingReadOverrides = <String, bool>{};
  final Map<String, Map<int, bool>> _pendingChapterOverrides =
      <String, Map<int, bool>>{};
  final Map<String, int> _pendingReadOps = <String, int>{};
  final Map<String, Map<int, int>> _pendingChapterOps =
      <String, Map<int, int>>{};
  final Map<String, Set<int>> _latestRawCheckedSnapshots = <String, Set<int>>{};
  final Map<String, bool> _latestBaseDoneSnapshots = <String, bool>{};
  final Map<String, int> _latestChapterCountSnapshots = <String, int>{};
  int _nextPendingOpId = 0;

  DateTime get _now => widget.currentDate ?? DateTime.now();

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<int, bool> _ensureChapterOverrideMap(String dateKey) =>
      _pendingChapterOverrides.putIfAbsent(dateKey, () => <int, bool>{});

  Map<int, int> _ensureChapterOpsMap(String dateKey) =>
      _pendingChapterOps.putIfAbsent(dateKey, () => <int, int>{});

  void _removeChapterOverride(String dateKey, int chapterIndex) {
    final overrides = _pendingChapterOverrides[dateKey];
    overrides?.remove(chapterIndex);
    if (overrides != null && overrides.isEmpty) {
      _pendingChapterOverrides.remove(dateKey);
    }
    final ops = _pendingChapterOps[dateKey];
    ops?.remove(chapterIndex);
    if (ops != null && ops.isEmpty) {
      _pendingChapterOps.remove(dateKey);
    }
  }

  void _scheduleChapterOverrideCleanup(String dateKey) {
    final snapshot = _latestRawCheckedSnapshots[dateKey];
    if (snapshot == null) {
      return;
    }
    _resolvePendingChapterOverridesFromSnapshot(
      dateKey: dateKey,
      rawChecked: snapshot,
    );
  }

  void _applyReadOverride(String dateKey, bool value, int opId) {
    _pendingReadOverrides[dateKey] = value;
    _pendingReadOps[dateKey] = opId;
  }

  void _revertReadOverride(String dateKey, bool? previousValue) {
    if (previousValue == null) {
      _pendingReadOverrides.remove(dateKey);
    } else {
      _pendingReadOverrides[dateKey] = previousValue;
    }
  }

  void _scheduleReadOverrideCleanup(String dateKey) {
    final rawSnapshot = _latestRawCheckedSnapshots[dateKey];
    final totalChapters = _latestChapterCountSnapshots[dateKey] ?? 0;
    final baseDone = _latestBaseDoneSnapshots[dateKey] ?? false;
    _resolvePendingReadOverrideFromSnapshot(
      dateKey: dateKey,
      hasChapters: totalChapters > 0,
      totalChapters: totalChapters,
      rawChecked: rawSnapshot ?? const <int>{},
      baseDone: baseDone,
    );
  }

  void _resolvePendingChapterOverridesFromSnapshot({
    required String dateKey,
    required Set<int> rawChecked,
  }) {
    final overrides = _pendingChapterOverrides[dateKey];
    if (overrides == null || overrides.isEmpty) {
      return;
    }

    final snapshotChecked = Set<int>.from(rawChecked);
    final pendingResolutions = <({int chapterIndex, int opId, bool desired})>[];
    overrides.forEach((chapterIndex, desired) {
      final opId = _pendingChapterOps[dateKey]?[chapterIndex];
      if (opId == null) {
        return;
      }
      final remoteHasChapter = snapshotChecked.contains(chapterIndex);
      if (remoteHasChapter == desired) {
        pendingResolutions.add((
          chapterIndex: chapterIndex,
          opId: opId,
          desired: desired,
        ));
      }
    });

    if (pendingResolutions.isEmpty) {
      return;
    }

    final latestSnapshot = _latestRawCheckedSnapshots[dateKey];
    final latestChecked = latestSnapshot != null
        ? Set<int>.from(latestSnapshot)
        : snapshotChecked;

    if (!mounted) {
      return;
    }

    final toRemove = <int>[];
    for (final resolution in pendingResolutions) {
      final currentOpId = _pendingChapterOps[dateKey]?[resolution.chapterIndex];
      final currentDesired =
          _pendingChapterOverrides[dateKey]?[resolution.chapterIndex];
      if (currentOpId != resolution.opId ||
          currentDesired != resolution.desired) {
        continue;
      }
      final remoteHasChapter = latestChecked.contains(resolution.chapterIndex);
      if (remoteHasChapter != resolution.desired) {
        continue;
      }
      toRemove.add(resolution.chapterIndex);
    }

    if (toRemove.isEmpty || !mounted) {
      return;
    }

    setState(() {
      for (final chapterIndex in toRemove) {
        _removeChapterOverride(dateKey, chapterIndex);
      }
    });
  }

  void _resolvePendingReadOverrideFromSnapshot({
    required String dateKey,
    required bool hasChapters,
    required int totalChapters,
    required Set<int> rawChecked,
    required bool baseDone,
  }) {
    final desired = _pendingReadOverrides[dateKey];
    final opId = _pendingReadOps[dateKey];
    if (desired == null || opId == null) {
      return;
    }

    final snapshotChecked = Set<int>.from(rawChecked);
    final remoteRead = hasChapters
        ? (totalChapters > 0 && snapshotChecked.length >= totalChapters)
        : baseDone;
    if (remoteRead != desired) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (_pendingReadOps[dateKey] != opId ||
        _pendingReadOverrides[dateKey] != desired) {
      return;
    }

    final latestRawChecked =
        _latestRawCheckedSnapshots[dateKey] ?? snapshotChecked;
    final latestChecked = Set<int>.from(latestRawChecked);
    final latestTotal = _latestChapterCountSnapshots[dateKey] ?? totalChapters;
    final latestBaseDone = _latestBaseDoneSnapshots[dateKey] ?? baseDone;
    final latestHasChapters = latestTotal > 0;
    final latestRemoteRead = latestHasChapters
        ? (latestTotal > 0 && latestChecked.length >= latestTotal)
        : latestBaseDone;

    if (latestRemoteRead != desired || !mounted) {
      return;
    }

    setState(() {
      _pendingReadOverrides.remove(dateKey);
      _pendingReadOps.remove(dateKey);
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleStream = widget.groupService.schedule(widget.group.id);
  }

  @override
  void didUpdateWidget(covariant GroupDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousUid = oldWidget.auth.currentUser?.uid;
    final currentUid = widget.auth.currentUser?.uid;
    final groupChanged = oldWidget.group.id != widget.group.id;
    final uidChanged = previousUid != currentUid;
    if (groupChanged || uidChanged) {
      setState(() {
        if (groupChanged) {
          _scheduleStream = widget.groupService.schedule(widget.group.id);
        }
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleScheduleReadToggle({
    required GroupSchedule schedule,
    required bool read,
    required Set<int> currentlyChecked,
    required bool hasChapters,
  }) {
    final dateKey = _dateKey(schedule.date);
    final opId = _nextPendingOpId++;
    final previousReadOverride = _pendingReadOverrides[dateKey];
    final previousChapterOverrides = _pendingChapterOverrides[dateKey] != null
        ? Map<int, bool>.from(_pendingChapterOverrides[dateKey]!)
        : null;
    final previousChapterOps = _pendingChapterOps[dateKey] != null
        ? Map<int, int>.from(_pendingChapterOps[dateKey]!)
        : null;
    final touchedChapters = <int>[];

    setState(() {
      _applyReadOverride(dateKey, read, opId);
      if (hasChapters) {
        final overrides = _ensureChapterOverrideMap(dateKey);
        final ops = _ensureChapterOpsMap(dateKey);
        for (var i = 0; i < schedule.chapters.length; i++) {
          overrides[i] = read;
          ops[i] = opId;
          touchedChapters.add(i);
        }
      }
    });

    unawaited(() async {
      final user = widget.auth.currentUser;
      if (user == null) return;

      final bool success = await widget.groupService.toggleReadStatus(
        groupId: widget.group.id,
        uid: user.uid,
        schedule: schedule,
        read: read,
        currentlyChecked: currentlyChecked,
      );

      if (!mounted) return;
      if (_pendingReadOps[dateKey] != opId) {
        return;
      }

      if (success) {
        _scheduleReadOverrideCleanup(dateKey);
        if (hasChapters) {
          final hasPendingForOp = touchedChapters.any(
            (index) => _pendingChapterOps[dateKey]?[index] == opId,
          );
          if (hasPendingForOp) {
            _scheduleChapterOverrideCleanup(dateKey);
          }
        }
        return;
      }
      setState(() {
        _pendingReadOps.remove(dateKey);
        _revertReadOverride(dateKey, previousReadOverride);
        if (hasChapters) {
          if (previousChapterOverrides == null) {
            _pendingChapterOverrides.remove(dateKey);
          } else {
            _pendingChapterOverrides[dateKey] = Map<int, bool>.from(
              previousChapterOverrides,
            );
          }
          if (previousChapterOps == null) {
            _pendingChapterOps.remove(dateKey);
          } else {
            _pendingChapterOps[dateKey] = Map<int, int>.from(
              previousChapterOps,
            );
          }
        }
      });
    }());
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberStream,
      builder: (context, membershipSnapshot) {
        final memberDoc = membershipSnapshot.data;
        final role = memberDoc?.data()?['role'] as String?;
        final isMember = isOwner || (memberDoc?.exists ?? false);
        final hasAdminPrivileges =
            isOwner || role == 'admin' || role == 'owner';

        return Scaffold(
          appBar: CommonStyles.buildAppBar(
            context,
            widget.group.name,
            actions: hasAdminPrivileges
                ? [
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1),
                      tooltip: 'Invite member',
                      onPressed: () {
                        unawaited(widget.vibrationService.lightImpact());
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InviteMemberPage(
                              group: widget.group,
                              groupService: widget.groupService,
                              friendService: widget.friendService,
                              auth: widget.auth,
                              vibrationService: widget.vibrationService,
                            ),
                          ),
                        );
                      },
                    ),
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
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit Group Plan',
                      onPressed: () {
                        unawaited(widget.vibrationService.lightImpact());
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditGroupPage(
                              group: widget.group,
                              groupService: widget.groupService,
                              auth: widget.auth,
                              vibrationService: widget.vibrationService,
                            ),
                          ),
                        );
                      },
                    ),
                  ]
                : null,
          ),
          body: Container(
            decoration: CommonStyles.backgroundDecoration(
              Theme.of(context).colorScheme,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<List<GroupSchedule>>(
                stream: _scheduleStream,
                builder: (context, snapshot) {
                  final schedule = snapshot.data ?? [];
                  final now = _now;
                  final today = DateTime(now.year, now.month, now.day);
                  final todaySchedule = schedule.where((s) {
                    final sDate =
                        DateTime(s.date.year, s.date.month, s.date.day);
                    return sDate.isAtSameMomentAs(today);
                  }).firstOrNull;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Join Request UI for non-members
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
                                padding: EdgeInsets.only(bottom: 24),
                                child: Text('Join request pending',
                                    textAlign: TextAlign.center),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: VibrationButton(
                                vibrationService: widget.vibrationService,
                                onPressed: () async {
                                  try {
                                    await widget.groupService.joinGroup(
                                      groupId: widget.group.id,
                                      uid: user.uid,
                                      name: user.displayName ?? '',
                                      photoUrl: user.photoURL,
                                      isPublic: widget.group.isPublic,
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(widget.group.isPublic
                                            ? 'Joined group'
                                            : 'Join request sent'),
                                      ),
                                    );
                                  } catch (e, st) {
                                    if (kDebugMode) {
                                      debugPrint('Failed to join group: $e');
                                    }
                                    ErrorLogger.log(e, st);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to join group'),
                                      ),
                                    );
                                  }
                                },
                                child: Text(widget.group.isPublic
                                    ? 'Join Group'
                                    : 'Request to Join'),
                              ),
                            );
                          },
                        ),
                      GroupProgressCard(
                        groupId: widget.group.id,
                        schedule: schedule,
                        groupService: widget.groupService,
                        currentDate: _now,
                        group: widget.group,
                        auth: widget.auth,
                        vibrationService: widget.vibrationService,
                      ),
                      const SizedBox(height: 24),
                      if (todaySchedule != null) ...[
                        TodaysReadingCard(
                          groupId: widget.group.id,
                          userId: widget.auth.currentUser?.uid ?? '',
                          schedule: todaySchedule,
                          groupService: widget.groupService,
                          vibrationService: widget.vibrationService,
                          isMember: isMember,
                          currentDate: _now,
                          pendingReadOverride: _pendingReadOverrides[
                              _dateKey(todaySchedule.date)],
                          pendingChapterOverrides: _pendingChapterOverrides[
                              _dateKey(todaySchedule.date)],
                          onToggle: ({
                            required read,
                            required currentlyChecked,
                            required hasChapters,
                          }) {
                            _handleScheduleReadToggle(
                              schedule: todaySchedule,
                              read: read,
                              currentlyChecked: currentlyChecked,
                              hasChapters: hasChapters,
                            );
                          },
                          onSnapshotsUpdated: ({
                            required rawChecked,
                            required baseDone,
                            required totalChapters,
                          }) {
                            final dateKey = _dateKey(todaySchedule.date);
                            _latestRawCheckedSnapshots[dateKey] = rawChecked;
                            _latestBaseDoneSnapshots[dateKey] = baseDone;
                            _latestChapterCountSnapshots[dateKey] =
                                totalChapters;
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      GroupMembersList(
                        groupId: widget.group.id,
                        groupService: widget.groupService,
                        currentDate: _now,
                      ),
                      if (isMember) ...[
                        const SizedBox(height: 24),
                        _buildLogProgressButton(context),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogProgressButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          unawaited(widget.vibrationService.lightImpact());
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupCatchUpPage(
                group: widget.group,
                groupService: widget.groupService,
                auth: widget.auth,
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
        icon: const Icon(Icons.history_rounded),
        label: const Text('Log Progress'),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
