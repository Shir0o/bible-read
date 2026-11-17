import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/circle_member.dart';
import 'error_logger.dart';
import 'group_collections.dart';
import 'milestone_announcer.dart';
import 'read_log_service.dart';

/// The Circle Feed, assembled from per-Group data that
/// already exists: each Group's daily read-log entries (Shown up,
/// an announced Milestone), their `likes`
/// (Amen), the Group's schedule and progress (what was read).
/// No collection of its own.
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

  /// Live raw Feed data across [groupIds] for the week ending [today]. Emits
  /// once every Group's entries have reported, along with the likes of every
  /// update they hold; a Group that errors contributes nothing rather than
  /// blocking the rest.
  Stream<FeedSource> watch(
    List<String> groupIds, {
    required DateTime today,
  }) {
    if (groupIds.isEmpty) {
      return Stream.value(const FeedSource());
    }
    final dateKeys = dateKeysFor(today);

    return Stream<FeedSource>.multi((controller) {
      final entries = <String, List<FeedEntryCopy>>{};
      final generation = <String, int>{};
      final expected = groupIds.length * dateKeys.length;
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      final likeSubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      final likers = <String, Set<String>>{};

      void emit() {
        if (controller.isClosed) return;
        if (entries.length < expected) return;
        if (likeSubs.keys.any((path) => !likers.containsKey(path))) return;
        controller.add(FeedSource(
          entries: [
            for (final list in entries.values)
              for (final e in list) e.withLikers(likers[e.likesPath] ?? {}),
          ],
        ));
      }

      /// Matches the likes listeners to the updates now held.
      void syncLikes() {
        final wanted = {
          for (final list in entries.values)
            for (final e in list) e.likesPath,
        };
        for (final path in likeSubs.keys.toList()) {
          if (wanted.contains(path)) continue;
          unawaited(likeSubs.remove(path)!.cancel());
          likers.remove(path);
        }
        for (final path in wanted) {
          if (likeSubs.containsKey(path)) continue;
          likeSubs[path] = firestore.collection(path).snapshots().listen(
            (snap) {
              likers[path] = {for (final d in snap.docs) d.id};
              emit();
            },
            onError: (Object e, StackTrace st) {
              unawaited(ErrorLogger.log(e, st));
              likers[path] = const {};
              emit();
            },
          );
        }
      }

      void put<T>(Map<String, List<T>> into, String key, List<T> value) {
        into[key] = value;
        syncLikes();
        emit();
      }

      /// Runs [load] for [key], keeping only the newest snapshot's result.
      void hydrate(String key, Future<List<FeedEntryCopy>> Function() load) {
        final gen = (generation[key] ?? 0) + 1;
        generation[key] = gen;
        load().then((value) {
          if (generation[key] != gen) return;
          put(entries, key, value);
        }, onError: (Object e, StackTrace st) {
          unawaited(ErrorLogger.log(e, st));
          if (generation[key] != gen) return;
          put(entries, key, const <FeedEntryCopy>[]);
        });
      }

      for (final groupId in groupIds) {
        for (final dateKey in dateKeys) {
          final key = 'g/$groupId/$dateKey';
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
              () => _entryCopies(groupId, dateKey, snap.docs),
            ),
            onError: (Object e, StackTrace st) {
              unawaited(ErrorLogger.log(e, st));
              put(entries, key, const <FeedEntryCopy>[]);
            },
          ));
        }
      }

      controller.onCancel = () {
        for (final sub in [...subs, ...likeSubs.values]) {
          unawaited(sub.cancel());
        }
      };
    });
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
    return [
      for (final doc in docs)
        FeedEntryCopy(
          groupId: groupId,
          dateKey: dateKey,
          uid: doc.id,
          name: doc.data()['name'] as String?,
          timestamp: (doc.data()['timestamp'] as Timestamp?)?.toDate(),
          milestone: FeedMilestone.fromMap(doc.data()['milestone']),
          reading: readings[doc.id],
        ),
    ];
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
      final ref = firestore.collection(t.likesPath).doc(uid);
      if (amen) {
        batch.set(ref, {'timestamp': Timestamp.now(), 'name': name});
      } else {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }
}

/// One copy of a person's daily entry in one Group.
class FeedEntryCopy {
  /// The Group this copy sits in.
  final String groupId;
  final String dateKey;
  final String uid;
  final String? name;
  final DateTime? timestamp;
  final FeedMilestone? milestone;
  final String? reading;
  final Set<String> likerUids;

  const FeedEntryCopy({
    required this.groupId,
    required this.dateKey,
    required this.uid,
    this.name,
    this.timestamp,
    this.milestone,
    this.reading,
    this.likerUids = const {},
  });

  String get likesPath =>
      '${GroupCollections.groups}/$groupId/read_log/$dateKey/entries/$uid/likes';

  FeedEntryCopy withLikers(Set<String> likers) => FeedEntryCopy(
        groupId: groupId,
        dateKey: dateKey,
        uid: uid,
        name: name,
        timestamp: timestamp,
        milestone: milestone,
        reading: reading,
        likerUids: likers,
      );
}

/// Everything the Feed is built from, across the reader's Groups.
class FeedSource {
  final List<FeedEntryCopy> entries;

  const FeedSource({this.entries = const []});
}

/// A read-log entry an Amen is written on.
class AmenTarget {
  final String groupId;
  final String dateKey;
  final String uid;

  const AmenTarget(
    this.groupId,
    this.dateKey,
    this.uid,
  );

  String get likesPath =>
      '${GroupCollections.groups}/$groupId/read_log/$dateKey/entries/$uid/likes';
}

enum FeedUpdateKind { day, grouped, milestone }

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

  /// Stable id: `dateKey/uid` or `dateKey/grouped`.
  final String key;
  final String dateKey;
  final DateTime? time;
  final List<FeedPerson> people;
  final Set<String> groupIds;
  final String? reading;
  final FeedMilestone? milestone;
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
    this.milestone,
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
List<FeedDay> assembleFeed({
  required FeedSource source,
  required String myUid,
  required String? myName,
  required String? myPhotoUrl,
  required List<CircleMember> circle,
  required Set<String> groupIds,
  required DateTime today,
}) {
  final circleByUid = {for (final m in circle) m.uid: m};
  final coMembers = {
    for (final m in circle)
      if (m.groupIds.any(groupIds.contains)) m.uid: m,
  };

  bool visibleEntry(FeedEntryCopy entry) {
    return groupIds.contains(entry.groupId) &&
        (entry.uid == myUid || coMembers.containsKey(entry.uid));
  }

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
    final member = circleByUid[uid];
    final full = member?.name ?? entryName ?? '';
    final first = full.trim().split(' ').first;
    return FeedPerson(
      uid: uid,
      name: first.isEmpty ? 'Someone' : first,
      photoUrl: member?.photoUrl,
    );
  }

  final copies = <String, List<FeedEntryCopy>>{};
  for (final e in source.entries) {
    if (!visibleEntry(e)) continue;
    copies.putIfAbsent('${e.dateKey}/${e.uid}', () => []).add(e);
  }

  final byDay = <String, List<FeedUpdate>>{};
  for (final MapEntry(:key, value: entryCopies) in copies.entries) {
    final [dateKey, uid] = key.split('/');
    final groups = {for (final c in entryCopies) c.groupId};
    final milestone = entryCopies.map((c) => c.milestone).nonNulls.firstOrNull;
    final times = entryCopies.map((c) => c.timestamp).nonNulls;
    final kind =
        milestone != null ? FeedUpdateKind.milestone : FeedUpdateKind.day;
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
          milestone: milestone,
          targets: [
            for (final c in entryCopies)
              AmenTarget(
                c.groupId,
                dateKey,
                uid,
              ),
          ],
          likerUids: {for (final c in entryCopies) ...c.likerUids},
        ));
  }

  int newestFirst(FeedUpdate a, FeedUpdate b) =>
      (b.time ?? DateTime(0)).compareTo(a.time ?? DateTime(0));

  final result = <FeedDay>[];
  for (final dateKey in FeedService.dateKeysFor(today)) {
    final updates = byDay[dateKey];
    if (updates == null) continue;
    final plain = updates.where((u) => u.kind == FeedUpdateKind.day).toList();
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
