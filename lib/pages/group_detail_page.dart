import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../services/achievement_service.dart';
import '../services/book_achievement_refresher.dart';
import '../services/error_logger.dart';
import '../services/group_book_achievement_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/group_members_section.dart';
import '../widgets/schedule_item_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/vibration_button.dart';
import 'edit_group_page.dart';
import 'group_join_requests_page.dart';

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

  /// Service used for achievement operations.
  final AchievementService achievementService;

  /// Aggregates completed chapters across joined groups.
  final GroupBookAchievementService groupBookAchievementService;

  /// Creates a [GroupDetailPage].
  factory GroupDetailPage({
    Key? key,
    required Group group,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
    GroupDatePicker? datePicker,
    AchievementService? achievementService,
    GroupBookAchievementService? groupBookAchievementService,
  }) {
    final resolvedGroupService = groupService ?? GroupService();
    final resolvedAchievementService = achievementService ??
        AchievementService(firestore: resolvedGroupService.firestore);
    final resolvedGroupBookAchievementService = groupBookAchievementService ??
        GroupBookAchievementService(
          firestore: resolvedGroupService.firestore,
          groupService: resolvedGroupService,
        );

    return GroupDetailPage._(
      key: key,
      group: group,
      groupService: resolvedGroupService,
      auth: auth ?? FirebaseAuth.instance,
      vibrationService: vibrationService ?? const VibrationService(),
      datePicker: datePicker ?? _defaultDatePicker,
      achievementService: resolvedAchievementService,
      groupBookAchievementService: resolvedGroupBookAchievementService,
    );
  }

  const GroupDetailPage._({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
    required this.datePicker,
    required this.achievementService,
    required this.groupBookAchievementService,
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
  late Stream<List<GroupMemberProgressData>> _memberOverallStream;
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
  StreamSubscription<Set<String>>? _achievementSubscription;
  Set<String> _unlockedAchievementIds = <String>{};
  late BookAchievementRefresher _bookAchievementRefresher;

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<int, bool> _ensureChapterOverrideMap(String dateKey) =>
      _pendingChapterOverrides.putIfAbsent(dateKey, () => <int, bool>{});

  Map<int, int> _ensureChapterOpsMap(String dateKey) =>
      _pendingChapterOps.putIfAbsent(dateKey, () => <int, int>{});

  void _applyChapterOverride(
    String dateKey,
    int chapterIndex,
    bool value,
    int opId,
  ) {
    _ensureChapterOverrideMap(dateKey)[chapterIndex] = value;
    _ensureChapterOpsMap(dateKey)[chapterIndex] = opId;
  }

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

  void _refreshAchievementSubscription() {
    _achievementSubscription?.cancel();
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      _unlockedAchievementIds = <String>{};
      return;
    }

    _achievementSubscription =
        widget.achievementService.unlockedAchievementIds(uid).listen(
      (ids) {
        if (!mounted) return;
        setState(() {
          _unlockedAchievementIds = ids;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Failed to load achievements: $error');
        }
        ErrorLogger.log(error, stackTrace);
      },
    );
  }

  Future<void> _refreshBookAchievements({
    required DateTime completionTimestamp,
  }) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      final result = await _bookAchievementRefresher.refresh(
        uid: uid,
        completionTimestamp: completionTimestamp,
        skipAchievementIds: _unlockedAchievementIds,
      );
      if (result.alreadyUnlockedAchievementIds.isNotEmpty && mounted) {
        setState(() {
          _unlockedAchievementIds = {
            ..._unlockedAchievementIds,
            ...result.alreadyUnlockedAchievementIds,
          };
        });
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to refresh book achievements: $error');
      }
      ErrorLogger.log(error, stackTrace);
    }
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
    _bookAchievementRefresher = BookAchievementRefresher(
      achievementService: widget.achievementService,
      groupBookAchievementService: widget.groupBookAchievementService,
    );
    _memberOverallStream = widget.groupService.memberOverallCompletion(
      widget.group.id,
      includeUid: widget.auth.currentUser?.uid,
    );
    _scheduleStream = widget.groupService.schedule(widget.group.id);
    _refreshAchievementSubscription();
  }

  @override
  void didUpdateWidget(covariant GroupDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousUid = oldWidget.auth.currentUser?.uid;
    final currentUid = widget.auth.currentUser?.uid;
    final groupChanged = oldWidget.group.id != widget.group.id;
    final uidChanged = previousUid != currentUid;
    final achievementServiceChanged =
        oldWidget.achievementService != widget.achievementService;
    final groupBookServiceChanged = oldWidget.groupBookAchievementService !=
        widget.groupBookAchievementService;
    if (groupChanged || uidChanged) {
      setState(() {
        if (groupChanged) {
          _scheduleStream = widget.groupService.schedule(widget.group.id);
        }
        _memberOverallStream = widget.groupService.memberOverallCompletion(
          widget.group.id,
          includeUid: currentUid,
        );
      });
    }
    if (uidChanged || achievementServiceChanged) {
      _refreshAchievementSubscription();
    }
    if (achievementServiceChanged || groupBookServiceChanged) {
      _bookAchievementRefresher = BookAchievementRefresher(
        achievementService: widget.achievementService,
        groupBookAchievementService: widget.groupBookAchievementService,
      );
    }
  }

  @override
  void dispose() {
    _achievementSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _toggleMyReadForDate(DateTime date, bool read) async {
    final user = widget.auth.currentUser;
    if (user == null) return false;
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
        await progressDoc.set({
          'done': true,
          'ts': Timestamp.now(),
          'uid': user.uid,
          'groupId': widget.group.id,
          'dateId': dateKey,
        }, SetOptions(merge: true));
      } else {
        await progressDoc.delete();
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle read: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update read status')),
      );
      return false;
    }
  }

  Future<bool> _toggleMyChapterForDate(
    DateTime date,
    int chapterIndex,
    bool read,
  ) async {
    final user = widget.auth.currentUser;
    if (user == null) return false;
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
        final snapshots =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
          tx.get(itemDoc),
          tx.get(base),
          tx.get(summaryDoc),
        ]);
        final itemSnap = snapshots[0];
        final baseSnap = snapshots[1];
        final summarySnap = snapshots[2];
        final nowTs = Timestamp.now();
        final prevCompleted =
            (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;

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
          tx.set(
              summaryDoc,
              {
                'completed': prevCompleted + 1,
              },
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
          final newCompleted = prevCompleted > 0 ? prevCompleted - 1 : 0;
          tx.set(
              summaryDoc,
              {
                'completed': newCompleted,
              },
              SetOptions(merge: true));
        }
      });
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle chapter: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update read status')),
      );
      return false;
    }
  }

  Future<bool> _setMyReadStatusForDate({
    required GroupSchedule schedule,
    required bool read,
    required Set<int> currentlyChecked,
  }) async {
    if (schedule.chapters.isEmpty) {
      return true;
    }
    final user = widget.auth.currentUser;
    if (user == null) return false;
    try {
      final target = DateTime(
        schedule.date.year,
        schedule.date.month,
        schedule.date.day,
      );
      final dateKey =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final db = widget.groupService.firestore;
      final entryRef = db
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid);
      final summaryRef = db
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(user.uid);

      await db.runTransaction((tx) async {
        final snapshots =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
          tx.get(entryRef),
          tx.get(summaryRef),
        ]);
        final entrySnap = snapshots[0];
        final summarySnap = snapshots[1];
        final nowTs = Timestamp.now();
        final currentCount = (entrySnap.data()?['count'] as num?)?.toInt() ??
            currentlyChecked.length;
        final desiredCount = read ? schedule.chapters.length : 0;
        final delta = desiredCount - currentCount;
        final itemsCollection = entryRef.collection('items');
        final prevCompleted =
            (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;

        if (read) {
          for (var i = 0; i < schedule.chapters.length; i++) {
            if (currentlyChecked.contains(i)) continue;
            tx.set(itemsCollection.doc(i.toString()), {
              'done': true,
              'ts': nowTs,
            });
          }
          tx.set(
              entryRef,
              {
                'done': true,
                'ts': nowTs,
                'uid': user.uid,
                'groupId': widget.group.id,
                'dateId': dateKey,
                'count': desiredCount,
              },
              SetOptions(merge: true));
        } else {
          if (currentlyChecked.isNotEmpty) {
            for (final idx in currentlyChecked) {
              tx.delete(itemsCollection.doc(idx.toString()));
            }
          }
          if (entrySnap.exists) {
            if (desiredCount == 0) {
              tx.delete(entryRef);
            } else {
              tx.update(entryRef, {'count': desiredCount, 'ts': nowTs});
            }
          }
        }

        if (delta != 0) {
          final updatedCompleted = prevCompleted + delta;
          tx.set(
              summaryRef,
              {
                'completed': updatedCompleted < 0 ? 0 : updatedCompleted,
              },
              SetOptions(merge: true));
        }
      });
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Failed to toggle read: $e');
      ErrorLogger.log(e, st);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update read status')),
      );
      return false;
    }
  }

  void _handleChapterToggle({
    required GroupSchedule schedule,
    required int chapterIndex,
    required bool read,
  }) {
    final dateKey = _dateKey(schedule.date);
    final opId = _nextPendingOpId++;

    setState(() {
      _applyChapterOverride(dateKey, chapterIndex, read, opId);
    });

    unawaited(() async {
      final success = await _toggleMyChapterForDate(
        schedule.date,
        chapterIndex,
        read,
      );
      if (!mounted) return;
      if (_pendingChapterOps[dateKey]?[chapterIndex] != opId) {
        return;
      }
      if (success) {
        _scheduleChapterOverrideCleanup(dateKey);
        if (read) {
          await _refreshBookAchievements(completionTimestamp: DateTime.now());
        }
      } else {
        setState(() => _removeChapterOverride(dateKey, chapterIndex));
      }
    }());
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
      final bool success = hasChapters
          ? await _setMyReadStatusForDate(
              schedule: schedule,
              read: read,
              currentlyChecked: currentlyChecked,
            )
          : await _toggleMyReadForDate(schedule.date, read);

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
        if (read) {
          await _refreshBookAchievements(completionTimestamp: DateTime.now());
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
            widget.group.name, // Use widget.group.name as it updates from firestore stream usually, but here group is static.
            // If group name updates in EditGroupPage, we want to reflect it.
            // But this widget might not rebuild if group param doesn't change.
            // For now, assume it's fine or user navigates back and forth.
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
                Theme.of(context).colorScheme),
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
                GroupMembersSection(
                  key: const ValueKey('group-members-section'),
                  title: 'Members',
                  membersStream: _memberOverallStream,
                ),
                const SectionHeader('Schedule'),
                StreamBuilder<List<GroupSchedule>>(
                  stream: _scheduleStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Failed to load schedule');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final schedule = snapshot.data!;
                    final hasEntries = schedule.isNotEmpty;

                    final children = <Widget>[];

                    if (!hasEntries) {
                      children.add(const Text('No schedule'));
                    } else {
                      final user = widget.auth.currentUser;
                      children.addAll(
                        schedule.asMap().entries.map((e) {
                          final s = e.value;
                          final baseTile = ScheduleItemTile(
                            schedule: s,
                            onEdit: null, // Removed inline edit
                            onDelete: null, // Removed inline delete
                          );
                          if (user == null || !isMember) {
                            return baseTile;
                          }
                          final dateKey = _dateKey(s.date);
                          final entryRef = widget.groupService.firestore
                              .collection(GroupCollections.groups)
                              .doc(widget.group.id)
                              .collection('progress')
                              .doc(dateKey)
                              .collection('entries')
                              .doc(user.uid);

                          return StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>>(
                            stream: entryRef.snapshots(),
                            builder: (context, entrySnap) {
                              final entryData = entrySnap.data?.data();
                              final baseDone = entryData?['done'] == true;
                              return StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream:
                                    entryRef.collection('items').snapshots(),
                                builder: (context, itemsSnap) {
                                  final rawChecked = <int>{};
                                  for (final d
                                      in itemsSnap.data?.docs ?? const []) {
                                    final idx = int.tryParse(d.id);
                                    if (idx != null) rawChecked.add(idx);
                                  }

                                  final rawCheckedSnapshot = Set<int>.from(
                                    rawChecked,
                                  );
                                  final totalChapters = s.chapters.length;
                                  final hasChapters = totalChapters > 0;

                                  _latestRawCheckedSnapshots[dateKey] =
                                      Set<int>.from(rawCheckedSnapshot);
                                  _latestBaseDoneSnapshots[dateKey] = baseDone;
                                  _latestChapterCountSnapshots[dateKey] =
                                      totalChapters;

                                  final pendingReadOverrideExists =
                                      _pendingReadOverrides.containsKey(
                                    dateKey,
                                  );
                                  final pendingChapterOverrideExists =
                                      (_pendingChapterOverrides[dateKey]
                                              ?.isNotEmpty ??
                                          false);

                                  if (pendingReadOverrideExists ||
                                      pendingChapterOverrideExists) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((
                                      _,
                                    ) {
                                      if (!mounted) return;
                                      final hasPendingChapterOverride =
                                          (_pendingChapterOverrides[dateKey]
                                                  ?.isNotEmpty ??
                                              false);
                                      final hasPendingReadOverride =
                                          _pendingReadOverrides.containsKey(
                                        dateKey,
                                      );
                                      if (hasPendingChapterOverride) {
                                        _resolvePendingChapterOverridesFromSnapshot(
                                          dateKey: dateKey,
                                          rawChecked: rawCheckedSnapshot,
                                        );
                                      }
                                      if (hasPendingReadOverride) {
                                        _resolvePendingReadOverrideFromSnapshot(
                                          dateKey: dateKey,
                                          hasChapters: hasChapters,
                                          totalChapters: totalChapters,
                                          rawChecked: rawCheckedSnapshot,
                                          baseDone: baseDone,
                                        );
                                      }
                                    });
                                  }

                                  final displayChecked = Set<int>.from(
                                    rawCheckedSnapshot,
                                  );
                                  final pendingChapterOverride =
                                      _pendingChapterOverrides[dateKey];
                                  if (pendingChapterOverride != null) {
                                    pendingChapterOverride.forEach((
                                      chapterIndex,
                                      value,
                                    ) {
                                      if (value) {
                                        displayChecked.add(chapterIndex);
                                      } else {
                                        displayChecked.remove(chapterIndex);
                                      }
                                    });
                                  }

                                  final allChecked = hasChapters &&
                                      displayChecked.length >= totalChapters;
                                  final pendingRead =
                                      _pendingReadOverrides[dateKey];

                                  bool? currentUserRead;
                                  ValueChanged<bool>? onToggleRead;
                                  if (hasChapters) {
                                    currentUserRead = pendingRead ?? allChecked;
                                    onToggleRead = (value) {
                                      if (value ==
                                          (pendingRead ?? allChecked)) {
                                        return;
                                      }
                                      _handleScheduleReadToggle(
                                        schedule: s,
                                        read: value,
                                        currentlyChecked: Set<int>.from(
                                          rawChecked,
                                        ),
                                        hasChapters: true,
                                      );
                                    };
                                  } else {
                                    currentUserRead = pendingRead ?? baseDone;
                                    onToggleRead = (value) {
                                      if (value == (pendingRead ?? baseDone)) {
                                        return;
                                      }
                                      _handleScheduleReadToggle(
                                        schedule: s,
                                        read: value,
                                        currentlyChecked: const <int>{},
                                        hasChapters: false,
                                      );
                                    };
                                  }

                                  return ScheduleItemTile(
                                    schedule: s,
                                    onEdit: null,
                                    onDelete: null,
                                    currentUserRead: currentUserRead,
                                    onToggleRead: onToggleRead,
                                    checkedChapters: displayChecked,
                                    onToggleChapter: (chapterIndex, v) {
                                      if (v ==
                                          displayChecked.contains(
                                            chapterIndex,
                                          )) {
                                        return;
                                      }
                                      _handleChapterToggle(
                                        schedule: s,
                                        chapterIndex: chapterIndex,
                                        read: v,
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        }),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
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
