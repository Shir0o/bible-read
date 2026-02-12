import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/achievement_service.dart';
import '../services/book_achievement_refresher.dart';
import '../services/error_logger.dart';
import '../services/group_book_achievement_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';

class FullSchedulePage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;
  final AchievementService achievementService;
  final GroupBookAchievementService groupBookAchievementService;

  factory FullSchedulePage({
    Key? key,
    required Group group,
    required GroupService groupService,
    required FirebaseAuth auth,
    required VibrationService vibrationService,
    AchievementService? achievementService,
    GroupBookAchievementService? groupBookAchievementService,
  }) {
    final resolvedAchievementService = achievementService ??
        AchievementService(firestore: groupService.firestore);
    final resolvedGroupBookAchievementService = groupBookAchievementService ??
        GroupBookAchievementService(
          firestore: groupService.firestore,
          groupService: groupService,
        );
    return FullSchedulePage._(
      key: key,
      group: group,
      groupService: groupService,
      auth: auth,
      vibrationService: vibrationService,
      achievementService: resolvedAchievementService,
      groupBookAchievementService: resolvedGroupBookAchievementService,
    );
  }

  const FullSchedulePage._({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
    required this.achievementService,
    required this.groupBookAchievementService,
  });

  @override
  State<FullSchedulePage> createState() => _FullSchedulePageState();
}

class _FullSchedulePageState extends State<FullSchedulePage> {
  late Stream<List<GroupSchedule>> _scheduleStream;
  
  // Logic from GroupDetailPage for optimistic updates
  final Map<String, bool> _pendingReadOverrides = <String, bool>{};
  final Map<String, Map<int, bool>> _pendingChapterOverrides = <String, Map<int, bool>>{};
  final Map<String, int> _pendingReadOps = <String, int>{};
  final Map<String, Map<int, int>> _pendingChapterOps = <String, Map<int, int>>{};
  final Map<String, Set<int>> _latestRawCheckedSnapshots = <String, Set<int>>{};
  final Map<String, bool> _latestBaseDoneSnapshots = <String, bool>{};
  final Map<String, int> _latestChapterCountSnapshots = <String, int>{};
  int _nextPendingOpId = 0;
  
  Set<String> _unlockedAchievementIds = <String>{};
  late BookAchievementRefresher _bookAchievementRefresher;
  StreamSubscription<Set<String>>? _achievementSubscription;

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
    if (snapshot == null) return;
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
    _achievementSubscription = widget.achievementService.unlockedAchievementIds(uid).listen(
      (ids) {
        if (!mounted) return;
        setState(() {
          _unlockedAchievementIds = ids;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) debugPrint('Failed to load achievements: $error');
        ErrorLogger.log(error, stackTrace);
      },
    );
  }

  Future<void> _refreshBookAchievements({required DateTime completionTimestamp}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

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
      if (kDebugMode) debugPrint('Failed to refresh book achievements: $error');
      ErrorLogger.log(error, stackTrace);
    }
  }

  void _resolvePendingChapterOverridesFromSnapshot({
    required String dateKey,
    required Set<int> rawChecked,
  }) {
    final overrides = _pendingChapterOverrides[dateKey];
    if (overrides == null || overrides.isEmpty) return;

    final snapshotChecked = Set<int>.from(rawChecked);
    final pendingResolutions = <({int chapterIndex, int opId, bool desired})>[];
    overrides.forEach((chapterIndex, desired) {
      final opId = _pendingChapterOps[dateKey]?[chapterIndex];
      if (opId == null) return;
      final remoteHasChapter = snapshotChecked.contains(chapterIndex);
      if (remoteHasChapter == desired) {
        pendingResolutions.add((chapterIndex: chapterIndex, opId: opId, desired: desired));
      }
    });

    if (pendingResolutions.isEmpty) return;

    final latestSnapshot = _latestRawCheckedSnapshots[dateKey];
    final latestChecked = latestSnapshot != null ? Set<int>.from(latestSnapshot) : snapshotChecked;

    if (!mounted) return;

    final toRemove = <int>[];
    for (final resolution in pendingResolutions) {
      final currentOpId = _pendingChapterOps[dateKey]?[resolution.chapterIndex];
      final currentDesired = _pendingChapterOverrides[dateKey]?[resolution.chapterIndex];
      if (currentOpId != resolution.opId || currentDesired != resolution.desired) continue;
      final remoteHasChapter = latestChecked.contains(resolution.chapterIndex);
      if (remoteHasChapter != resolution.desired) continue;
      toRemove.add(resolution.chapterIndex);
    }

    if (toRemove.isEmpty || !mounted) return;

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
    if (desired == null || opId == null) return;

    final snapshotChecked = Set<int>.from(rawChecked);
    final remoteRead = hasChapters
        ? (totalChapters > 0 && snapshotChecked.length >= totalChapters)
        : baseDone;
    if (remoteRead != desired) return;

    if (!mounted) return;

    if (_pendingReadOps[dateKey] != opId || _pendingReadOverrides[dateKey] != desired) return;

    final latestRawChecked = _latestRawCheckedSnapshots[dateKey] ?? snapshotChecked;
    final latestChecked = Set<int>.from(latestRawChecked);
    final latestTotal = _latestChapterCountSnapshots[dateKey] ?? totalChapters;
    final latestBaseDone = _latestBaseDoneSnapshots[dateKey] ?? baseDone;
    final latestHasChapters = latestTotal > 0;
    final latestRemoteRead = latestHasChapters
        ? (latestTotal > 0 && latestChecked.length >= latestTotal)
        : latestBaseDone;

    if (latestRemoteRead != desired || !mounted) return;

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
  void dispose() {
    _achievementSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _toggleMyReadForDate(DateTime date, bool read) async {
    final user = widget.auth.currentUser;
    if (user == null) return false;
    try {
      final target = DateTime(date.year, date.month, date.day);
      final dateKey = _dateKey(target);
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
      ErrorLogger.log(e, st);
      return false;
    }
  }

  Future<bool> _setMyReadStatusForDate({
    required GroupSchedule schedule,
    required bool read,
    required Set<int> currentlyChecked,
  }) async {
    if (schedule.chapters.isEmpty) return true;
    final user = widget.auth.currentUser;
    if (user == null) return false;
    try {
      final target = DateTime(schedule.date.year, schedule.date.month, schedule.date.day);
      final dateKey = _dateKey(target);
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
        final snapshots = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
          tx.get(entryRef),
          tx.get(summaryRef),
        ]);
        final entrySnap = snapshots[0];
        final summarySnap = snapshots[1];
        final nowTs = Timestamp.now();
        final currentCount = (entrySnap.data()?['count'] as num?)?.toInt() ?? currentlyChecked.length;
        final desiredCount = read ? schedule.chapters.length : 0;
        final delta = desiredCount - currentCount;
        final itemsCollection = entryRef.collection('items');
        final prevCompleted = (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;

        if (read) {
          for (var i = 0; i < schedule.chapters.length; i++) {
            if (currentlyChecked.contains(i)) continue;
            tx.set(itemsCollection.doc(i.toString()), {'done': true, 'ts': nowTs});
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
            SetOptions(merge: true),
          );
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
          tx.set(summaryRef, {'completed': updatedCompleted < 0 ? 0 : updatedCompleted}, SetOptions(merge: true));
        }
      });
      return true;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return false;
    }
  }

  void _handleScheduleReadToggle({
    required GroupSchedule schedule,
    required bool read,
    required Set<int> currentlyChecked,
    required bool hasChapters,
  }) {
    widget.vibrationService.lightImpact();
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
      if (_pendingReadOps[dateKey] != opId) return;

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
            _pendingChapterOverrides[dateKey] = Map<int, bool>.from(previousChapterOverrides);
          }
          if (previousChapterOps == null) {
            _pendingChapterOps.remove(dateKey);
          } else {
            _pendingChapterOps[dateKey] = Map<int, int>.from(previousChapterOps);
          }
        }
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.auth.currentUser;
    final isMember = user != null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
        centerTitle: true,
        title: Text(
          'Full Schedule',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<List<GroupSchedule>>(
        stream: _scheduleStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final schedule = snapshot.data!;
          if (schedule.isEmpty) return const Center(child: Text('No schedule available'));

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          final past = schedule.where((s) => s.date.isBefore(today)).toList();
          final present = schedule.where((s) => s.date.isAtSameMomentAs(today)).toList();
          final upcoming = schedule.where((s) => s.date.isAfter(today)).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (past.isNotEmpty) ...[
                  _SectionHeader(title: 'Past Readings'),
                  ...past.map((s) => _buildScheduleItem(s, user, isMember, isPast: true)),
                  const SizedBox(height: 16),
                ],
                if (present.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'TODAY',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...present.map((s) => _buildScheduleItem(s, user, isMember, isToday: true)),
                  const SizedBox(height: 16),
                ],
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(title: 'Upcoming'),
                  ...upcoming.map((s) => _buildScheduleItem(s, user, isMember)),
                  const SizedBox(height: 80),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleItem(GroupSchedule s, User? user, bool isMember, {bool isPast = false, bool isToday = false}) {
    if (user == null) return const SizedBox.shrink();
    
    final dateKey = _dateKey(s.date);
    final entryRef = widget.groupService.firestore
        .collection(GroupCollections.groups)
        .doc(widget.group.id)
        .collection('progress')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
            final totalChapters = s.chapters.length;
            final hasChapters = totalChapters > 0;

            _latestRawCheckedSnapshots[dateKey] = Set<int>.from(rawCheckedSnapshot);
            _latestBaseDoneSnapshots[dateKey] = baseDone;
            _latestChapterCountSnapshots[dateKey] = totalChapters;

            // Resolve pending overrides logic
            final pendingReadOverrideExists = _pendingReadOverrides.containsKey(dateKey);
            final pendingChapterOverrideExists = (_pendingChapterOverrides[dateKey]?.isNotEmpty ?? false);

            if (pendingReadOverrideExists || pendingChapterOverrideExists) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if ((_pendingChapterOverrides[dateKey]?.isNotEmpty ?? false)) {
                    _resolvePendingChapterOverridesFromSnapshot(dateKey: dateKey, rawChecked: rawCheckedSnapshot);
                  }
                  if (_pendingReadOverrides.containsKey(dateKey)) {
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

            final displayChecked = Set<int>.from(rawCheckedSnapshot);
            final pendingChapterOverride = _pendingChapterOverrides[dateKey];
            if (pendingChapterOverride != null) {
              pendingChapterOverride.forEach((chapterIndex, value) {
                if (value) {
                  displayChecked.add(chapterIndex);
                } else {
                  displayChecked.remove(chapterIndex);
                }
              });
            }

            final allChecked = hasChapters && displayChecked.length >= totalChapters;
            final pendingRead = _pendingReadOverrides[dateKey];
            
            bool isCompleted;
            if (hasChapters) {
              isCompleted = pendingRead ?? allChecked;
            } else {
              isCompleted = pendingRead ?? baseDone;
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScheduleCard(
                schedule: s,
                isCompleted: isCompleted,
                isPast: isPast,
                isToday: isToday,
                onToggle: (v) {
                  _handleScheduleReadToggle(
                    schedule: s,
                    read: v,
                    currentlyChecked: Set<int>.from(rawChecked),
                    hasChapters: hasChapters,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final GroupSchedule schedule;
  final bool isCompleted;
  final bool isPast;
  final bool isToday;
  final ValueChanged<bool> onToggle;

  const _ScheduleCard({
    required this.schedule,
    required this.isCompleted,
    required this.isPast,
    required this.isToday,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final month = _monthName(schedule.date.month);
    final day = schedule.date.day.toString();
    final weekday = _weekdayName(schedule.date.weekday);
    final title = schedule.chapters.join(', ');

    Color cardColor = colorScheme.surfaceContainerHighest;
    double opacity = 1.0;
    BoxBorder? border;
    List<BoxShadow>? shadows;
    
    if (isPast) {
      opacity = 0.7;
    } else if (isToday) {
      cardColor = colorScheme.surfaceContainerHighest;
      border = Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1);
      shadows = [
        BoxShadow(
          color: colorScheme.primary.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        )
      ];
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(isToday ? 20 : 12),
          border: border,
          boxShadow: shadows,
        ),
        child: InkWell(
          onTap: () => onToggle(!isCompleted),
          borderRadius: BorderRadius.circular(isToday ? 20 : 12),
          child: Padding(
            padding: EdgeInsets.all(isToday ? 20 : 16),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$month $day',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: isToday ? 14 : 12,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                          color: isToday ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        weekday,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: isToday ? colorScheme.primary.withValues(alpha: 0.8) : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: isToday ? 20 : 18,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                          color: colorScheme.onSurface.withValues(alpha: isPast ? 0.8 : 1.0),
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Daily Reading',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CheckCircle(
                  isChecked: isCompleted,
                  isToday: isToday,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _weekdayName(int weekday) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    // DateTime.weekday 1 = Mon, 7 = Sun. Array is 0-indexed.
    // If array is ['Sun', 'Mon', ...], then Sun is index 0.
    // But standard Gregorian is Sunday=1?
    // Dart DateTime.weekday: Monday=1, Sunday=7.
    // My array: 0=Sun, 1=Mon...
    // If weekday is 7 (Sun), I want index 0. if 1 (Mon), I want index 1.
    // index = weekday % 7.
    return days[weekday % 7];
  }
}

class _CheckCircle extends StatelessWidget {
  final bool isChecked;
  final bool isToday;
  final ColorScheme colorScheme;

  const _CheckCircle({
    required this.isChecked,
    required this.isToday,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (isChecked) {
      return Icon(
        Icons.check_circle,
        color: colorScheme.primary,
        size: isToday ? 32 : 28,
      );
    }

    return Container(
      width: isToday ? 24 : 24,
      height: isToday ? 24 : 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isToday ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.4),
          width: isToday ? 2 : 1,
        ),
      ),
    );
  }
}
