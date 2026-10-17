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

  /// The server's per-award badge history under each Group.
  static const String badgeLog = 'badge_log';

  /// Live raw Feed data across [groupIds] for the week ending [today]. Emits
  /// once every Group's entries and badge log have reported, along with the
  /// likes of every update they hold; a Group that errors contributes
  /// nothing rather than blocking the rest.
  ///
  /// Likes are watched live, one listener per update in the week (an entry
  /// or a logged badge), so another reader's Amen shows at once. Listeners
  /// follow the updates: one whose update is gone is cancelled.
  Stream<FeedSource> watch(List<String> groupIds, {required DateTime today}) {
    if (groupIds.isEmpty) return Stream.value(const FeedSource());
    final dateKeys = dateKeysFor(today);
    final oldest = DateTime(today.year, today.month, today.day - (days - 1));

    return Stream<FeedSource>.multi((controller) {
      final entries = <String, List<FeedEntryCopy>>{};
      final badges = <String, List<FeedBadgeCopy>>{};
      final generation = <String, int>{};
      final expected = groupIds.length * (dateKeys.length + 1);
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      final likeSubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      final likers = <String, Set<String>>{};

      void emit() {
        if (controller.isClosed) return;
        if (entries.length + badges.length < expected) return;
        if (likeSubs.keys.any((path) => !likers.containsKey(path))) return;
        controller.add(FeedSource(
          entries: [
            for (final list in entries.values)
              for (final e in list) e.withLikers(likers[e.likesPath] ?? {}),
          ],
          badges: [
            for (final list in badges.values)
              for (final b in list) b.withLikers(likers[b.likesPath] ?? {}),
          ],
        ));
      }

      /// Matches the likes listeners to the updates now held.
      void syncLikes() {
        final wanted = {
          for (final list in entries.values)
            for (final e in list) e.likesPath,
          for (final list in badges.values)
            for (final b in list) b.likesPath,
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
              () => _entryCopies(groupId, dateKey, snap.docs),
            ),
            onError: (Object e, StackTrace st) {
              unawaited(ErrorLogger.log(e, st));
              put(entries, key, const <FeedEntryCopy>[]);
            },
          ));
        }

        subs.add(firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection(badgeLog)
            .where('dateUnlocked',
                isGreaterThanOrEqualTo: Timestamp.fromDate(oldest))
            .snapshots()
            .listen(
          (snap) => put(
            badges,
            groupId,
            _badgeCopies(groupId, dateKeys.toSet(), snap.docs),
          ),
          onError: (Object e, StackTrace st) {
            unawaited(ErrorLogger.log(e, st));
            put(badges, groupId, const <FeedBadgeCopy>[]);
          },
        ));
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
          sharedReflection: _reflection(doc.data()['sharedReflection']),
          milestone: FeedMilestone.fromMap(doc.data()['milestone']),
          reading: readings[doc.id],
        ),
    ];
  }

  static String? _reflection(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  List<FeedBadgeCopy> _badgeCopies(
    String groupId,
    Set<String> dateKeys,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      [
        for (final doc in docs)
          FeedBadgeCopy(
            groupId: groupId,
            awardId: doc.id,
            mirror: BadgeMirror.fromFirestore(
              (doc.data()['uid'] as String?) ?? '',
              doc,
            ),
          ),
      ]
          .where((b) =>
              b.mirror.uid.isNotEmpty &&
              b.mirror.dateUnlocked != null &&
              dateKeys
                  .contains(ReadLogService.dateKeyFor(b.mirror.dateUnlocked!)))
          .toList();

  /// Writes (or, with [amen] false, deletes) [uid]'s Amen on every entry or
  /// logged badge in [targets] — one like per Group the update came from.
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

  String get likesPath => AmenTarget(groupId, dateKey, uid).likesPath;

  FeedEntryCopy withLikers(Set<String> likers) => FeedEntryCopy(
        groupId: groupId,
        dateKey: dateKey,
        uid: uid,
        name: name,
        timestamp: timestamp,
        sharedReflection: sharedReflection,
        milestone: milestone,
        reading: reading,
        likerUids: likers,
      );
}

/// One Group's log of a badge a member was awarded, with the Amens on that
/// badge alone.
class FeedBadgeCopy {
  final String groupId;

  /// The badge log document id, `{uid}_{badgeId}`.
  final String awardId;
  final BadgeMirror mirror;
  final Set<String> likerUids;

  const FeedBadgeCopy({
    required this.groupId,
    required this.awardId,
    required this.mirror,
    this.likerUids = const {},
  });

  String get dateKey => ReadLogService.dateKeyFor(mirror.dateUnlocked!);

  AmenTarget get target =>
      AmenTarget(groupId, dateKey, mirror.uid, awardId: awardId);

  String get likesPath => target.likesPath;

  FeedBadgeCopy withLikers(Set<String> likers) => FeedBadgeCopy(
        groupId: groupId,
        awardId: awardId,
        mirror: mirror,
        likerUids: likers,
      );
}

/// Everything the Feed is built from, across the reader's Groups.
class FeedSource {
  final List<FeedEntryCopy> entries;
  final List<FeedBadgeCopy> badges;

  const FeedSource({this.entries = const [], this.badges = const []});
}

/// A read-log entry, or with [awardId] a logged badge, an Amen is written on.
class AmenTarget {
  final String groupId;
  final String dateKey;
  final String uid;
  final String? awardId;

  const AmenTarget(this.groupId, this.dateKey, this.uid, {this.awardId});

  String get likesPath => awardId == null
      ? '${GroupCollections.groups}/$groupId/read_log/$dateKey/entries/$uid/likes'
      : '${GroupCollections.groups}/$groupId/${FeedService.badgeLog}/$awardId/likes';
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

  /// Stable id: `dateKey/uid`, `dateKey/grouped`, or `dateKey/awardId` for
  /// a Badge.
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
/// takes the day, else the person's day (keeping a shared Reflection if any
/// copy carries one). Each Badge earned is an update of its own, with its
/// own Amens. Two or more same-day people with no Reflection collapse into
/// one grouped update. Days run newest first and days with nothing are left
/// out.
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
    badgeCopies.putIfAbsent('${b.dateKey}/${b.awardId}', () => []).add(b);
  }

  final byDay = <String, List<FeedUpdate>>{};
  for (final MapEntry(:key, value: badges) in badgeCopies.entries) {
    final badge = badges.first;
    byDay.putIfAbsent(badge.dateKey, () => []).add(FeedUpdate(
          kind: FeedUpdateKind.badge,
          key: key,
          dateKey: badge.dateKey,
          time: badge.mirror.dateUnlocked,
          people: [person(badge.mirror.uid, null)],
          groupIds: {for (final b in badges) b.groupId},
          badgeTitle: badge.mirror.title,
          targets: [for (final b in badges) b.target],
          likerUids: {for (final b in badges) ...b.likerUids},
        ));
  }
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
          reflection:
              entryCopies.map((c) => c.sharedReflection).nonNulls.firstOrNull,
          milestone: milestone,
          targets: [for (final g in groups) AmenTarget(g, dateKey, uid)],
          likerUids: {for (final c in entryCopies) ...c.likerUids},
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
