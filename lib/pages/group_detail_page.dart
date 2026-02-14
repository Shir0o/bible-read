import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
import '../widgets/vibration_button.dart';
import 'edit_group_page.dart';
import 'group_join_requests_page.dart';
import 'full_schedule_page.dart';

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

  /// Date to consider as "today" (for testing).
  final DateTime? currentDate;

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
    DateTime? currentDate,
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
      currentDate: currentDate,
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
  StreamSubscription<Set<String>>? _achievementSubscription;
  Set<String> _unlockedAchievementIds = <String>{};
  late BookAchievementRefresher _bookAchievementRefresher;

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
          await _refreshBookAchievements(completionTimestamp: _now);
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
                                    );
                                    if (!context.mounted) return;
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
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to join group'),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Join Group'),
                              ),
                            );
                          },
                        ),
                      _buildGroupProgress(context, schedule),
                      const SizedBox(height: 24),
                      _buildTodaysReading(context, schedule,
                          isMember: isMember),
                      const SizedBox(height: 24),
                      _buildMembersList(context),
                      const SizedBox(height: 24),
                      _buildFullScheduleButton(context),
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

  Widget _buildGroupProgress(
      BuildContext context, List<GroupSchedule> schedule) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate progress
    int totalChapters = 0;
    int completedChapters = 0;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);

    String? currentBook;

    for (var s in schedule) {
      totalChapters += s.chapters.length;
      if (s.date.isBefore(today) || s.date.isAtSameMomentAs(today)) {
        completedChapters += s.chapters.length;
      }
      if (s.date.isAtSameMomentAs(today) && s.chapters.isNotEmpty) {
        // Simple parsing: assuming format "Book Chapter"
        final firstChapter = s.chapters.first;
        final parts = firstChapter.split(' ');
        if (parts.length > 1) {
          // Handle "1 John" cases
          if (int.tryParse(parts[0]) != null && parts.length > 2) {
            currentBook = '${parts[0]} ${parts[1]}';
          } else {
            currentBook = parts[0];
          }
        } else {
          currentBook = parts[0];
        }
      }
    }

    final percent = totalChapters > 0 ? completedChapters / totalChapters : 0.0;
    final percentDisplay = (percent * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GROUP PROGRESS',
                    style: GoogleFonts.plusJakartaSans(
                      textStyle: theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$percentDisplay%',
                    style: GoogleFonts.plusJakartaSans(
                      textStyle: theme.textTheme.displaySmall,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'On Track',
                  style: GoogleFonts.plusJakartaSans(
                    textStyle: theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 16,
              backgroundColor:
                  colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            currentBook != null
                ? 'The group is $percentDisplay% through the Book of $currentBook.'
                : 'The group is $percentDisplay% through the reading plan.',
            style: GoogleFonts.plusJakartaSans(
              textStyle: theme.textTheme.bodyMedium,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaysReading(BuildContext context, List<GroupSchedule> schedule,
      {required bool isMember}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);

    final todaySchedule = schedule.where((s) {
      final sDate = DateTime(s.date.year, s.date.month, s.date.day);
      return sDate.isAtSameMomentAs(today);
    }).firstOrNull;

    if (todaySchedule == null) {
      return const SizedBox.shrink();
    }

    final dateString = _formatDate(now);
    final readingTitle = todaySchedule.chapters.join(', ');

    // Logic for "My Read Status"
    final dateKey = _dateKey(todaySchedule.date);
    final entryRef = widget.groupService.firestore
        .collection(GroupCollections.groups)
        .doc(widget.group.id)
        .collection('progress')
        .doc(dateKey)
        .collection('entries')
        .doc(widget.auth.currentUser?.uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Reading",
          style: GoogleFonts.plusJakartaSans(
            textStyle: theme.textTheme.titleMedium,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                dateString,
                style: GoogleFonts.plusJakartaSans(
                  textStyle: theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                readingTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  textStyle: theme.textTheme.headlineSmall,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle placeholder if needed
              // Text('Life in the Spirit', ...),
              const SizedBox(height: 24),

              if (isMember)
                // Read Button Logic
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: entryRef.snapshots(),
                  builder: (context, entrySnap) {
                    final entryData = entrySnap.data?.data();
                    final baseDone = entryData?['done'] == true;

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: entryRef.collection('items').snapshots(),
                        builder: (context, itemsSnap) {
                          final rawChecked = <int>{};
                          for (final d in itemsSnap.data?.docs ?? const []) {
                            final idx = int.tryParse(d.id);
                            if (idx != null) rawChecked.add(idx);
                          }

                          final rawCheckedSnapshot = Set<int>.from(rawChecked);
                          final totalChapters = todaySchedule.chapters.length;
                          final hasChapters = totalChapters > 0;

                          // Update snapshots for override logic
                          _latestRawCheckedSnapshots[dateKey] =
                              Set<int>.from(rawCheckedSnapshot);
                          _latestBaseDoneSnapshots[dateKey] = baseDone;
                          _latestChapterCountSnapshots[dateKey] = totalChapters;

                          // Check for pending overrides
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            final hasPendingChapterOverride =
                                (_pendingChapterOverrides[dateKey]
                                        ?.isNotEmpty ??
                                    false);
                            final hasPendingReadOverride =
                                _pendingReadOverrides.containsKey(dateKey);
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

                          final pendingRead = _pendingReadOverrides[dateKey];
                          // Determine effective read status
                          final isRead = hasChapters
                              ? (pendingRead ??
                                  (totalChapters > 0 &&
                                      rawCheckedSnapshot.length >=
                                          totalChapters))
                              : (pendingRead ?? baseDone);

                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                unawaited(
                                    widget.vibrationService.lightImpact());
                                _handleScheduleReadToggle(
                                  schedule: todaySchedule,
                                  read: !isRead,
                                  currentlyChecked: rawCheckedSnapshot,
                                  hasChapters: hasChapters,
                                );
                              },
                              icon: Icon(
                                Icons.check_circle,
                                color: isRead
                                    ? colorScheme.onPrimary
                                    : colorScheme.onPrimary
                                        .withValues(alpha: 0.7),
                                fill: isRead
                                    ? 1.0
                                    : 0.0, // Material Symbols fill if supported
                              ),
                              label: Text(isRead ? 'Read' : 'Mark as Read'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isRead
                                    ? colorScheme.primary
                                    : colorScheme.primary.withValues(
                                        alpha: 0.8), // Purple Expressive
                                foregroundColor: colorScheme.onPrimary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: isRead ? 0 : 4,
                                textStyle: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        });
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMembersList(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Members',
              style: GoogleFonts.plusJakartaSans(
                textStyle: theme.textTheme.titleMedium,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            StreamBuilder<List<GroupMemberProgressData>>(
              stream: widget.groupService.memberDailyCompletion(
                widget.group.id,
                date: _now,
              ),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return Text(
                  '$count Members',
                  style: GoogleFonts.plusJakartaSans(
                    textStyle: theme.textTheme.bodySmall,
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: StreamBuilder<List<GroupMemberProgressData>>(
            stream: widget.groupService.memberDailyCompletion(
              widget.group.id,
              date: _now,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Failed to load members'));
              }
              if (!snapshot.hasData) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()));
              }
              final members = snapshot.data!;
              if (members.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: Text('No members'));
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                separatorBuilder: (context, index) => Divider(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final isRead = member.completion >= 1.0;
                  final statusText = isRead ? 'Read today' : 'Not yet';

                  return Semantics(
                    label: '${member.name}, $statusText',
                    container: true,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: ClipOval(
                              child: member.photoUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: member.photoUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const Icon(Icons.person),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.person),
                                    )
                                  : const Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Semantics(
                              excludeSemantics: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      textStyle: theme.textTheme.bodyLarge,
                                      fontWeight: FontWeight.w500,
                                      color: isRead
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.8),
                                    ),
                                  ),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.plusJakartaSans(
                                      textStyle: theme.textTheme.bodySmall,
                                      fontWeight: FontWeight.w500,
                                      color: isRead
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            message: isRead
                                ? 'Completed reading for today'
                                : 'Has not read today',
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRead
                                    ? colorScheme.primary
                                        .withValues(alpha: 0.2)
                                    : Colors.transparent,
                                border: isRead
                                    ? null
                                    : Border.all(
                                        color: colorScheme.outline
                                            .withValues(alpha: 0.3),
                                      ),
                              ),
                              child: Center(
                                child: Icon(
                                  isRead ? Icons.check : Icons.hourglass_empty,
                                  size: 18,
                                  color: isRead
                                      ? colorScheme.primary
                                      : colorScheme.outline
                                          .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFullScheduleButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () {
          unawaited(widget.vibrationService.lightImpact());
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FullSchedulePage(
                group: widget.group,
                groupService: widget.groupService,
                auth: widget.auth,
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
        icon: Icon(Icons.calendar_month, color: colorScheme.primary),
        label: Text('View Full Schedule',
            style: TextStyle(color: colorScheme.primary)),
        style: TextButton.styleFrom(
          backgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
