import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/badge_award.dart';
import '../models/circle_member.dart';
import 'error_logger.dart';
import 'group_collections.dart';
import 'milestone_announcer.dart';
import 'read_log_service.dart';

/// The Circle Feed (ADR-0011), assembled only from per-Group data that
/// already exists (ADR-0004): each Group's daily read-log entries (Shown up,
/// the shared Reflection copy, an announced Milestone), their `likes`
/// (Amen), the Group's schedule and progress (what was read), and the
/// per-Group badge mirror. No collection of its own.
class FeedService {
  FeedService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  /// Today plus the previous seven days.
  static const int days = 8;

  /// The date keys the Feed covers, newest first.
  static List<String> dateKeysFor(DateTime today) => [
        for (var i = 0; i < days; i++)
          ReadLogService.dateKeyFor(
            DateTime(today.year, today.month, today.day - i),
          ),
      ];

  DocumentReference<Map<String, dynamic>> _entry(
    String groupId,
    String dateKey,
    String uid,
  ) =>
      firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(uid);

  /// Live raw Feed data across [groupIds] for the week ending [today]. Emits
  /// once every Group's entries and badge mirror have reported; a Group that
  /// errors contributes nothing rather than blocking the rest.
  Stream<FeedSource> watch(List<String> groupIds, {required DateTime today}) {
    if (groupIds.isEmpty) return Stream.value(const FeedSource());
    final dateKeys = dateKeysFor(today);

    return Stream<FeedSource>.multi((controller) {
      final entries = <String, List<FeedEntryCopy>>{};
      final badges = <String, List<FeedBadgeCopy>>{};
      final generation = <String, int>{};
      final expected = groupIds.length * (dateKeys.length + 1);
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        if (controller.isClosed) return;
        if (entries.length + badges.length < expected) return;
        controller.add(FeedSource(
          entries: [for (final list in entries.values) ...list],
          badges: [for (final list in badges.values) ...list],
        ));
      }

      /// Runs [load] for [key], keeping only the newest snapshot's result.
      void hydrate<T>(
        String key,
        Map<String, List<T>> into,
        Future<List<T>> Function() load,
      ) {
        final gen = (generation[key] ?? 0) + 1;
        generation[key] = gen;
        load().then((value) {
          if (generation[key] != gen) return;
          into[key] = value;
          emit();
        }, onError: (Object e, StackTrace st) {
          unawaited(ErrorLogger.log(e, st));
          if (generation[key] != gen) return;
          into[key] = const [];
          emit();
        });
      }

      for (final groupId in groupIds) {
        for (final dateKey in dateKeys) {
          final key = '$groupId/$dateKey';
          subs.add(firestore
              .collection(GroupCollections.groups)
              .doc(groupId)
              .collection('read_log')
              .doc(dateKey)
              .collection('entries')
              .snapshots()
              .listen(
            (snap) => hydrate(
              key,
              entries,
              () => _entryCopies(groupId, dateKey, snap.docs),
            ),
            onError: (Object e, StackTrace st) {
              unawaited(ErrorLogger.log(e, st));
              entries[key] = const [];
              emit();
            },
          ));
        }

        subs.add(firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection('badges')
            .snapshots()
            .listen(
          (snap) => hydrate(
            groupId,
            badges,
            () => _badgeCopies(groupId, dateKeys.toSet(), snap.docs),
          ),
          onError: (Object e, StackTrace st) {
            unawaited(ErrorLogger.log(e, st));
            badges[groupId] = const [];
            emit();
          },
        ));
      }

      controller.onCancel = () {
        for (final sub in subs) {
          unawaited(sub.cancel());
        }
      };
    });
  }

  Future<Set<String>> _likers(
      String groupId, String dateKey, String uid) async {
    final likes = await _entry(groupId, dateKey, uid).collection('likes').get();
    return likes.docs.map((d) => d.id).toSet();
  }

  /// What each person read on [dateKey] in [groupId]: the day's scheduled
  /// chapters, for members whose progress shows them read. Empty when the
  /// Group has no schedule that day.
  Future<Map<String, String>> _readings(String groupId, String dateKey) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final schedule = await groupRef
          .collection(GroupCollections.schedule)
          .doc(dateKey)
          .get();
      final chapters = (schedule.data()?['chapters'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      if (chapters.isEmpty) return const {};
      final progress = await groupRef
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .get();
      return {
        for (final doc in progress.docs)
          if (((doc.data()['count'] as num?)?.toInt() ?? 0) > 0 ||
              doc.data()['done'] == true)
            doc.id: chapters.join(', '),
      };
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      return const {};
    }
  }

  Future<List<FeedEntryCopy>> _entryCopies(
    String groupId,
    String dateKey,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return const [];
    final readings = await _readings(groupId, dateKey);
    return Future.wait([
      for (final doc in docs)
        _likers(groupId, dateKey, doc.id).then((likers) {
          final data = doc.data();
          final reflection = data['sharedReflection'];
          return FeedEntryCopy(
            groupId: groupId,
            dateKey: dateKey,
            uid: doc.id,
            name: data['name'] as String?,
            timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
            sharedReflection:
                reflection is String && reflection.trim().isNotEmpty
                    ? reflection.trim()
                    : null,
            milestone: FeedMilestone.fromMap(data['milestone']),
            reading: readings[doc.id],
            likerUids: likers,
          );
        }),
    ]);
  }

  Future<List<FeedBadgeCopy>> _badgeCopies(
    String groupId,
    Set<String> dateKeys,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final inWeek = [
      for (final doc in docs) BadgeMirror.fromFirestore(doc.id, doc),
    ].where((m) =>
        m.dateUnlocked != null &&
        dateKeys.contains(ReadLogService.dateKeyFor(m.dateUnlocked!)));
    return Future.wait([
      for (final mirror in inWeek)
        _likers(
          groupId,
          ReadLogService.dateKeyFor(mirror.dateUnlocked!),
          mirror.uid,
        ).then((likers) => FeedBadgeCopy(
              groupId: groupId,
              mirror: mirror,
              likerUids: likers,
            )),
    ]);
  }

  /// Writes (or, with [amen] false, deletes) [uid]'s Amen on every entry in
  /// [targets] — one like per Group the update came from.
  Future<void> setAmen({
    required List<AmenTarget> targets,
    required String uid,
    required String name,
    required bool amen,
  }) async {
    final batch = firestore.batch();
    for (final t in targets) {
      final ref =
          _entry(t.groupId, t.dateKey, t.uid).collection('likes').doc(uid);
      if (amen) {
        batch.set(ref, {'timestamp': Timestamp.now(), 'name': name});
      } else {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }
}

/// One copy of a person's daily entry, in one Group.
class FeedEntryCopy {
  final String groupId;
  final String dateKey;
  final String uid;
  final String? name;
  final DateTime? timestamp;
  final String? sharedReflection;
  final FeedMilestone? milestone;
  final String? reading;
  final Set<String> likerUids;

  const FeedEntryCopy({
    required this.groupId,
    required this.dateKey,
    required this.uid,
    this.name,
    this.timestamp,
    this.sharedReflection,
    this.milestone,
    this.reading,
    this.likerUids = const {},
  });
}

/// One Group's mirror of a member's latest badge, with the Amens on that
/// member's entry for the unlock day.
class FeedBadgeCopy {
  final String groupId;
  final BadgeMirror mirror;
  final Set<String> likerUids;

  const FeedBadgeCopy({
    required this.groupId,
    required this.mirror,
    this.likerUids = const {},
  });
}

/// Everything the Feed is built from, across the reader's Groups.
class FeedSource {
  final List<FeedEntryCopy> entries;
  final List<FeedBadgeCopy> badges;

  const FeedSource({this.entries = const [], this.badges = const []});
}

/// A read-log entry an Amen is written on.
class AmenTarget {
  final String groupId;
  final String dateKey;
  final String uid;

  const AmenTarget(this.groupId, this.dateKey, this.uid);
}

enum FeedUpdateKind { day, grouped, milestone, badge }

/// Someone named on an update.
class FeedPerson {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isMe;

  /// The name the avatar's initial comes from ("Alice" for "You").
  final String avatarName;

  const FeedPerson({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.isMe = false,
    String? avatarName,
  }) : avatarName = avatarName ?? name;
}

/// One update in the Feed.
class FeedUpdate {
  final FeedUpdateKind kind;

  /// Stable id: `dateKey/uid`, or `dateKey/grouped`.
  final String key;
  final String dateKey;
  final DateTime? time;
  final List<FeedPerson> people;
  final Set<String> groupIds;
  final String? reading;
  final String? reflection;
  final FeedMilestone? milestone;
  final String? badgeTitle;
  final List<AmenTarget> targets;
  final Set<String> likerUids;

  const FeedUpdate({
    required this.kind,
    required this.key,
    required this.dateKey,
    required this.people,
    required this.groupIds,
    required this.targets,
    required this.likerUids,
    this.time,
    this.reading,
    this.reflection,
    this.milestone,
    this.badgeTitle,
  });
}

/// One day heading's worth of updates, newest first.
class FeedDay {
  final String dateKey;
  final DateTime date;
  final List<FeedUpdate> updates;

  const FeedDay(this.dateKey, this.date, this.updates);
}

/// Builds the Feed from [source], narrowed to [groupIds] and to people the
/// reader shares one of those Groups with.
///
/// One update per person per day, deduplicated across Groups: a Milestone
/// takes the day, then a Badge, then the person's day (keeping a shared
/// Reflection if any copy carries one). Two or more same-day people with no
/// Reflection collapse into one grouped update. Days run newest first and
/// days with nothing are left out.
List<FeedDay> assembleFeed({
  required FeedSource source,
  required String myUid,
  required String? myName,
  required String? myPhotoUrl,
  required List<CircleMember> circle,
  required Set<String> groupIds,
  required DateTime today,
}) {
  final members = {
    for (final m in circle)
      if (m.groupIds.any(groupIds.contains)) m.uid: m,
  };
  bool visible(String uid, String groupId) =>
      groupIds.contains(groupId) && (uid == myUid || members.containsKey(uid));

  FeedPerson person(String uid, String? entryName) {
    if (uid == myUid) {
      return FeedPerson(
        uid: uid,
        name: 'You',
        photoUrl: myPhotoUrl,
        isMe: true,
        avatarName: myName,
      );
    }
    final full = members[uid]?.name ?? entryName ?? '';
    final first = full.trim().split(' ').first;
    return FeedPerson(
      uid: uid,
      name: first.isEmpty ? 'Someone' : first,
      photoUrl: members[uid]?.photoUrl,
    );
  }

  final copies = <String, List<FeedEntryCopy>>{};
  for (final e in source.entries) {
    if (!visible(e.uid, e.groupId)) continue;
    copies.putIfAbsent('${e.dateKey}/${e.uid}', () => []).add(e);
  }
  final badgeCopies = <String, List<FeedBadgeCopy>>{};
  for (final b in source.badges) {
    if (!visible(b.mirror.uid, b.groupId)) continue;
    final dateKey = ReadLogService.dateKeyFor(b.mirror.dateUnlocked!);
    badgeCopies.putIfAbsent('$dateKey/${b.mirror.uid}', () => []).add(b);
  }

  final byDay = <String, List<FeedUpdate>>{};
  for (final key in {...copies.keys, ...badgeCopies.keys}) {
    final [dateKey, uid] = key.split('/');
    final entryCopies = copies[key] ?? const <FeedEntryCopy>[];
    final badges = badgeCopies[key] ?? const <FeedBadgeCopy>[];
    final groups = {
      for (final c in entryCopies) c.groupId,
      for (final b in badges) b.groupId,
    };
    final milestone = entryCopies.map((c) => c.milestone).nonNulls.firstOrNull;
    final badge = badges.firstOrNull?.mirror;
    final times = [
      ...entryCopies.map((c) => c.timestamp).nonNulls,
      if (badge?.dateUnlocked != null) badge!.dateUnlocked!,
    ];
    final kind = milestone != null
        ? FeedUpdateKind.milestone
        : badge != null
            ? FeedUpdateKind.badge
            : FeedUpdateKind.day;
    byDay.putIfAbsent(dateKey, () => []).add(FeedUpdate(
          kind: kind,
          key: key,
          dateKey: dateKey,
          time: times.isEmpty
              ? null
              : times.reduce((a, b) => a.isAfter(b) ? a : b),
          people: [person(uid, entryCopies.firstOrNull?.name)],
          groupIds: groups,
          reading: entryCopies.map((c) => c.reading).nonNulls.firstOrNull,
          reflection:
              entryCopies.map((c) => c.sharedReflection).nonNulls.firstOrNull,
          milestone: milestone,
          badgeTitle: kind == FeedUpdateKind.badge ? badge!.title : null,
          targets: [for (final g in groups) AmenTarget(g, dateKey, uid)],
          likerUids: {
            for (final c in entryCopies) ...c.likerUids,
            for (final b in badges) ...b.likerUids,
          },
        ));
  }

  int newestFirst(FeedUpdate a, FeedUpdate b) =>
      (b.time ?? DateTime(0)).compareTo(a.time ?? DateTime(0));

  final result = <FeedDay>[];
  for (final dateKey in FeedService.dateKeysFor(today)) {
    final updates = byDay[dateKey];
    if (updates == null) continue;
    final plain = updates
        .where((u) => u.kind == FeedUpdateKind.day && u.reflection == null)
        .toList();
    if (plain.length >= 2) {
      plain.sort(newestFirst);
      updates.removeWhere(plain.contains);
      // The reader's own avatar trails: "Ben, Eli and you".
      final ordered = [
        ...plain.where((u) => !u.people.first.isMe),
        ...plain.where((u) => u.people.first.isMe),
      ];
      updates.add(FeedUpdate(
        kind: FeedUpdateKind.grouped,
        key: '$dateKey/grouped',
        dateKey: dateKey,
        time: plain.first.time,
        people: [for (final u in ordered) u.people.first],
        groupIds: {for (final u in plain) ...u.groupIds},
        // Amen celebrates the others; the reader never Amens themselves.
        targets: [
          for (final u in plain)
            if (!u.people.first.isMe) ...u.targets,
        ],
        likerUids: {
          for (final u in plain)
            if (!u.people.first.isMe) ...u.likerUids,
        },
      ));
    }
    updates.sort(newestFirst);
    final parts = dateKey.split('-').map(int.parse).toList();
    result
        .add(FeedDay(dateKey, DateTime(parts[0], parts[1], parts[2]), updates));
  }
  return result;
}
