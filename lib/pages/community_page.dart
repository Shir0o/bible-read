import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/circle_member.dart';
import '../models/group.dart';
import '../services/circle_service.dart';
import '../services/error_logger.dart';
import '../services/feed_service.dart';
import '../services/group_service.dart';
import '../services/nudge_service.dart';
import '../services/read_log_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_header.dart';
import '../widgets/common_styles.dart';
import '../widgets/community/empty_group_state.dart';
import '../widgets/group_preview_sheet.dart';
import '../widgets/nudge_sheet.dart';
import '../widgets/skeleton.dart';
import '../widgets/skeleton_loader.dart';
import 'group_members_page.dart';
import 'share_code_page.dart';

/// The Circle tab is the Feed (ADR-0011): a status row of everyone the
/// reader shares a Group with (ringed when Shown up today; tap to Nudge),
/// above a seven-day Feed of updates readers can Amen. Group filter chips
/// narrow both. Group actions live behind the header's Invite slot.
class CommunityPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GroupService groupService;
  final CircleService circleService;
  final ReadingStatusService readingStatusService;
  final VibrationService vibrationService;
  final NudgeService? nudgeService;
  final FeedService? feedService;

  /// Tells an update's author someone said Amen (the `sendLikeNotification`
  /// callable). Null sends nothing.
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  })? onSendLikeNotification;

  final DateTime Function() dateProvider;

  CommunityPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.groupService,
    CircleService? circleService,
    required this.readingStatusService,
    required this.vibrationService,
    this.nudgeService,
    this.feedService,
    this.onSendLikeNotification,
    required this.dateProvider,
  }) : circleService = circleService ?? groupService.circleService;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with AutomaticKeepAliveClientMixin {
  /// The Group the filter chips narrow to, or null for the whole Circle.
  String? _filterGroupId;

  String? _groupsUid;
  Stream<List<Group>>? _groupsStream;

  late final NudgeService _nudgeService =
      widget.nudgeService ?? NudgeService(firestore: widget.firestore);

  @override
  bool get wantKeepAlive => true;

  Stream<List<Group>> _groupsFor(String uid) {
    if (_groupsUid != uid || _groupsStream == null) {
      _groupsUid = uid;
      _groupsStream = widget.groupService.groupsForUser(uid);
    }
    return _groupsStream!;
  }

  void _openInvite(List<Group> groups) {
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => _InviteSheet(
        groups: groups,
        onSelected: (action) {
          Navigator.of(sheetContext).pop();
          action(context);
        },
        auth: widget.auth,
        firestore: widget.firestore,
        groupService: widget.groupService,
        nudgeService: _nudgeService,
        vibrationService: widget.vibrationService,
        dateProvider: widget.dateProvider,
      ),
    );
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = widget.auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<List<Group>>(
          stream: _groupsFor(user.uid),
          builder: (context, groupsSnap) {
            final groups = groupsSnap.data;
            if (_filterGroupId != null &&
                !(groups ?? const <Group>[])
                    .any((g) => g.id == _filterGroupId)) {
              _filterGroupId = null;
            }
            final selected = _filterGroupId == null
                ? null
                : groups!.firstWhere((g) => g.id == _filterGroupId);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: AppHeader(
                      auth: widget.auth,
                      firestore: widget.firestore,
                      vibrationService: widget.vibrationService,
                      dateProvider: widget.dateProvider,
                      eyebrow: selected?.name ?? 'Together',
                      title: 'Circle',
                      action: AppHeaderAction(
                        label: 'Invite',
                        onPressed: () => _openInvite(groups ?? const <Group>[]),
                      ),
                    ),
                  ),
                  if (groups != null && groups.isEmpty) ...[
                    const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.gap8)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: AppSpacing.horizontal,
                        child: EmptyGroupState(
                          auth: widget.auth,
                          firestore: widget.firestore,
                          groupService: widget.groupService,
                          vibrationService: widget.vibrationService,
                        ),
                      ),
                    ),
                  ] else
                    SliverToBoxAdapter(
                      child: _CircleFeed(
                        groups: groups,
                        selectedGroupId: _filterGroupId,
                        onSelectGroup: (id) =>
                            setState(() => _filterGroupId = id),
                        auth: widget.auth,
                        circleService: widget.circleService,
                        feedService: widget.feedService ??
                            FeedService(firestore: widget.firestore),
                        nudgeService: _nudgeService,
                        vibrationService: widget.vibrationService,
                        onSendLikeNotification: widget.onSendLikeNotification,
                        dateProvider: widget.dateProvider,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "Everyone" chip plus one chip per Group; selecting narrows the status row
/// and the Feed to that Group.
class _GroupFilterChips extends StatelessWidget {
  final List<Group> groups;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const _GroupFilterChips({
    required this.groups,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = AppColors.of(context);

    Widget buildChip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.gap8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          // Padded to a 48px target; the strip's gaps absorb the extra.
          materialTapTargetSize: MaterialTapTargetSize.padded,
          padding: EdgeInsets.zero,
          labelPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.gap12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
          ),
          side: BorderSide(
            color: selected ? colors.primaryLine : colors.border,
          ),
          selectedColor: colors.primarySoft,
          backgroundColor: Colors.transparent,
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          onSelected: (_) => onTap(),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.horizontal,
        children: [
          buildChip(
            label: 'Everyone',
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          for (final group in groups)
            buildChip(
              label: group.name,
              selected: selectedId == group.id,
              onTap: () => onSelected(group.id),
            ),
        ],
      ),
    );
  }
}

/// Chips, status row and Feed. Subscribes once across all the reader's
/// Groups and narrows locally, so switching chips is instant. [groups] is
/// null while the reader's Groups are still loading.
class _CircleFeed extends StatefulWidget {
  final List<Group>? groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelectGroup;
  final FirebaseAuth auth;
  final CircleService circleService;
  final FeedService feedService;
  final NudgeService nudgeService;
  final VibrationService vibrationService;
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  })? onSendLikeNotification;
  final DateTime Function() dateProvider;

  const _CircleFeed({
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectGroup,
    required this.auth,
    required this.circleService,
    required this.feedService,
    required this.nudgeService,
    required this.vibrationService,
    required this.onSendLikeNotification,
    required this.dateProvider,
  });

  @override
  State<_CircleFeed> createState() => _CircleFeedState();
}

class _CircleFeedState extends State<_CircleFeed> {
  String _groupKey = '';
  Stream<List<CircleMember>>? _circle;
  Stream<FeedSource>? _feed;

  /// Optimistic Amen state by update key; dropped once the source agrees.
  final Map<String, bool> _amenOverrides = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _CircleFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribe();
  }

  void _subscribe() {
    final groups = widget.groups;
    final uid = widget.auth.currentUser?.uid;
    if (groups == null || uid == null) return;
    final ids = groups.map((g) => g.id).toList()..sort();
    final key = '$uid|${ids.join(',')}';
    if (key == _groupKey) return;
    _groupKey = key;
    _circle = widget.circleService.watchCircleMembers(uid);
    _feed = widget.feedService.watch(ids, today: widget.dateProvider());
  }

  String get _myFirstName =>
      (widget.auth.currentUser?.displayName ?? '').trim().split(' ').first;

  bool _amened(FeedUpdate u, String myUid) =>
      _amenOverrides[u.key] ?? u.likerUids.contains(myUid);

  Future<void> _toggleAmen(FeedUpdate update) async {
    final user = widget.auth.currentUser;
    if (user == null || update.targets.isEmpty) return;
    final was = _amened(update, user.uid);
    widget.vibrationService.lightImpact();
    setState(() => _amenOverrides[update.key] = !was);
    final name = _myFirstName.isEmpty ? 'Someone' : _myFirstName;
    try {
      await widget.feedService.setAmen(
        targets: update.targets,
        uid: user.uid,
        name: name,
        amen: !was,
      );
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _amenOverrides.remove(update.key));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(was
            ? 'Couldn\'t remove your Amen. Please try again.'
            : 'Couldn\'t send your Amen. Please try again.'),
      ));
      return;
    }
    if (was) return;
    final send = widget.onSendLikeNotification;
    if (send == null) return;
    for (final owner in {for (final t in update.targets) t.uid}) {
      if (owner == user.uid) continue;
      try {
        await send(ownerUid: owner, likerName: name);
      } catch (e, st) {
        // The Amen itself landed; a missed notification is not a rollback.
        unawaited(ErrorLogger.log(e, st));
      }
    }
  }

  void _nudge(_StatusPerson person) {
    final user = widget.auth.currentUser;
    if (user == null) return;
    showNudgeSheet(
      context,
      person: NudgePerson(name: person.name, photoUrl: person.photoUrl),
      vibrationService: widget.vibrationService,
      onSend: (_) => widget.nudgeService.nudgeMember(
        currentUid: user.uid,
        memberUid: person.uid,
        currentName: _myFirstName.isEmpty ? 'Someone' : _myFirstName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final user = widget.auth.currentUser;
    final colors = AppColors.of(context);

    return StreamBuilder<List<CircleMember>>(
      stream: _circle,
      builder: (context, circleSnap) {
        return StreamBuilder<FeedSource>(
          stream: _feed,
          builder: (context, feedSnap) {
            final loading = groups == null ||
                user == null ||
                !circleSnap.hasData ||
                !feedSnap.hasData;

            Widget statusRow = const SizedBox.shrink();
            Widget feed = const SizedBox.shrink();
            if (!loading) {
              final selected = widget.selectedGroupId == null
                  ? groups.map((g) => g.id).toSet()
                  : {widget.selectedGroupId!};
              final today = widget.dateProvider();
              final days = assembleFeed(
                source: feedSnap.data!,
                myUid: user.uid,
                myName: user.displayName,
                myPhotoUrl: user.photoURL,
                circle: circleSnap.data!,
                groupIds: selected,
                today: today,
              );
              // Optimistic overrides retire once the source agrees.
              for (final day in days) {
                for (final u in day.updates) {
                  if (_amenOverrides[u.key] == u.likerUids.contains(user.uid)) {
                    _amenOverrides.remove(u.key);
                  }
                }
              }
              statusRow = _StatusRow(
                people: _statusPeople(
                  source: feedSnap.data!,
                  circle: circleSnap.data!,
                  selected: selected,
                  user: user,
                  todayKey: ReadLogService.dateKeyFor(today),
                ),
                onNudge: _nudge,
              );
              feed = _FeedList(
                days: days,
                today: today,
                groupNames: {for (final g in groups) g.id: g.name},
                isAmened: (u) => _amened(u, user.uid),
                amenCount: (u) {
                  final source = u.likerUids.contains(user.uid);
                  final now = _amened(u, user.uid);
                  return u.likerUids.length +
                      (now == source ? 0 : (now ? 1 : -1));
                },
                onAmen: _toggleAmen,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (groups != null && groups.isNotEmpty)
                  _GroupFilterChips(
                    groups: groups,
                    selectedId: widget.selectedGroupId,
                    onSelected: widget.onSelectGroup,
                  ),
                const SizedBox(height: AppSpacing.gap8),
                SkeletonLoader(
                  loading: loading,
                  skeleton: const _StatusRowSkeleton(),
                  child: statusRow,
                ),
                Padding(
                  padding: AppSpacing.horizontal,
                  child:
                      Divider(height: AppSpacing.gap24, color: colors.border),
                ),
                SkeletonLoader(
                  loading: loading,
                  skeleton: const _FeedSkeleton(),
                  child: feed,
                ),
                const SizedBox(height: AppSpacing.gap32),
              ],
            );
          },
        );
      },
    );
  }

  /// The reader first, then not-yet (who a Nudge reaches), then shown up
  /// with the freshest mark first.
  List<_StatusPerson> _statusPeople({
    required FeedSource source,
    required List<CircleMember> circle,
    required Set<String> selected,
    required User user,
    required String todayKey,
  }) {
    final marks = <String, DateTime>{};
    for (final e in source.entries) {
      if (e.dateKey != todayKey || !selected.contains(e.groupId)) continue;
      final t = e.timestamp ?? DateTime(0);
      if (marks[e.uid] == null || t.isAfter(marks[e.uid]!)) marks[e.uid] = t;
    }
    final others = [
      for (final m in circle)
        if (m.groupIds.any(selected.contains))
          _StatusPerson(
            uid: m.uid,
            name: (m.name ?? 'Reader').trim().split(' ').first,
            photoUrl: m.photoUrl,
            shownUp: marks.containsKey(m.uid),
          ),
    ]..sort((a, b) {
        if (a.shownUp != b.shownUp) return a.shownUp ? 1 : -1;
        return (marks[b.uid] ?? DateTime(0))
            .compareTo(marks[a.uid] ?? DateTime(0));
      });
    return [
      _StatusPerson(
        uid: user.uid,
        name: 'You',
        photoUrl: user.photoURL,
        shownUp: marks.containsKey(user.uid),
        isMe: true,
        avatarName: user.displayName,
      ),
      ...others,
    ];
  }
}

class _StatusPerson {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool shownUp;
  final bool isMe;
  final String? avatarName;

  const _StatusPerson({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.shownUp,
    this.isMe = false,
    this.avatarName,
  });
}

/// Today's status across the Circle: a solid ring for Shown up, a dashed one
/// for not yet. Tapping a not-yet person opens the Nudge sheet.
class _StatusRow extends StatelessWidget {
  final List<_StatusPerson> people;
  final ValueChanged<_StatusPerson> onNudge;

  const _StatusRow({required this.people, required this.onNudge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = AppColors.of(context);
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.horizontal,
        children: [
          for (final p in people)
            Padding(
              key: ValueKey('status_${p.uid}'),
              padding: const EdgeInsets.only(right: AppSpacing.gap12),
              child: Semantics(
                button: !p.isMe && !p.shownUp,
                label: p.shownUp
                    ? '${p.name}, shown up today'
                    : p.isMe
                        ? '${p.name}, not yet today'
                        : '${p.name}, not yet today. Nudge',
                excludeSemantics: true,
                child: InkWell(
                  onTap: !p.isMe && !p.shownUp ? () => onNudge(p) : null,
                  borderRadius: BorderRadius.circular(AppSpacing.rChip),
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        CustomPaint(
                          painter: _RingPainter(
                            color: p.shownUp
                                ? colorScheme.primary
                                : colors.primaryLine,
                            dashed: !p.shownUp,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.gap4),
                            child: _PersonAvatar(
                              name: p.avatarName ?? p.name,
                              photoUrl: p.photoUrl,
                              size: 48,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.gap4),
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: p.shownUp
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  const _RingPainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    if (!dashed) {
      canvas.drawOval(rect, paint);
      return;
    }
    const dashes = 18;
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.dashed != dashed;
}

class _PersonAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;
  final double size;

  const _PersonAvatar({
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()[0].toUpperCase()
        : null;
    final fallback = initial == null
        ? Icon(
            Icons.person_outline_rounded,
            size: size / 2,
            color: colorScheme.onSurfaceVariant,
          )
        : Text(
            initial,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: size * 0.36,
                ),
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => fallback,
              errorWidget: (context, url, error) => fallback,
            )
          : fallback,
    );
  }
}

/// The Feed: day headings over updates, newest first, closing on
/// "That's the week". Today with nothing posted reads as not-yet.
class _FeedList extends StatelessWidget {
  final List<FeedDay> days;
  final DateTime today;
  final Map<String, String> groupNames;
  final bool Function(FeedUpdate) isAmened;
  final int Function(FeedUpdate) amenCount;
  final ValueChanged<FeedUpdate> onAmen;

  const _FeedList({
    required this.days,
    required this.today,
    required this.groupNames,
    required this.isAmened,
    required this.amenCount,
    required this.onAmen,
  });

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _heading(FeedDay day) {
    final keys = FeedService.dateKeysFor(today);
    if (day.dateKey == keys[0]) return 'TODAY';
    if (day.dateKey == keys[1]) return 'YESTERDAY';
    final d = day.date;
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final todayKey = FeedService.dateKeysFor(today).first;
    final hasToday = days.isNotEmpty && days.first.dateKey == todayKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasToday)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding,
                AppSpacing.gap24, AppSpacing.hPadding, AppSpacing.gap24),
            child: Column(
              children: [
                Text(
                  'No updates yet today',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.gap4),
                Text(
                  'When someone in your Circle reads, it shows up here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding,
                AppSpacing.gap16, AppSpacing.hPadding, AppSpacing.gap8),
            child: Text(
              _heading(day),
              style: AppTextStyles.caption(context).copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
          for (final update in day.updates)
            _UpdateTile(
              key: ValueKey('feed_${update.key}'),
              update: update,
              isToday: day.dateKey == todayKey,
              groupNames: groupNames,
              amened: isAmened(update),
              amenCount: amenCount(update),
              onAmen: () => onAmen(update),
            ),
        ],
        if (days.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.gap24),
            child: Text(
              'That\'s the week',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateTile extends StatelessWidget {
  final FeedUpdate update;
  final bool isToday;
  final Map<String, String> groupNames;
  final bool amened;
  final int amenCount;
  final VoidCallback onAmen;

  const _UpdateTile({
    super.key,
    required this.update,
    required this.isToday,
    required this.groupNames,
    required this.amened,
    required this.amenCount,
    required this.onAmen,
  });

  static String _time(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String get _headline {
    final name = update.people.first.name;
    switch (update.kind) {
      case FeedUpdateKind.milestone:
        return '$name finished the ${update.milestone!.scope.label}';
      case FeedUpdateKind.badge:
        return '$name earned the ${update.badgeTitle} badge';
      case FeedUpdateKind.day:
        return update.reading != null
            ? '$name read ${update.reading}'
            : '$name showed up';
      case FeedUpdateKind.grouped:
        final names = [
          for (final p in update.people) p.isMe ? 'you' : p.name,
        ];
        final who = names.length > 3
            ? '${names[0]}, ${names[1]} and ${names.length - 2} others'
            : names.length == 2
                ? '${names[0]} and ${names[1]}'
                : '${names[0]}, ${names[1]} and ${names[2]}';
        return '$who read${isToday ? ' today' : ''}';
    }
  }

  String get _meta {
    final groups = [
      for (final id in update.groupIds)
        if (groupNames[id] != null) groupNames[id]!,
    ]..sort();
    return [
      if (update.time != null) _time(update.time!),
      if (groups.isNotEmpty) groups.join(', '),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMilestone = update.kind == FeedUpdateKind.milestone;

    final Widget leading = switch (update.kind) {
      FeedUpdateKind.grouped => _StackedAvatars(people: update.people),
      FeedUpdateKind.badge => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.of(context).accentSoft,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.workspace_premium_rounded,
            size: AppSpacing.iconMd,
            color: colorScheme.tertiary,
          ),
        ),
      _ => _PersonAvatar(
          name: update.people.first.avatarName,
          photoUrl: update.people.first.photoUrl,
          size: 40,
        ),
    };

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: AppSpacing.gap12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMilestone) ...[
                Text(
                  'MILESTONE',
                  style: AppTextStyles.caption(context).copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.gap2),
              ],
              Text(
                _headline,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isMilestone
                      ? colorScheme.onTertiaryContainer
                      : colorScheme.onSurface,
                ),
              ),
              if (_meta.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.gap2),
                Text(
                  _meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isMilestone
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (update.reflection != null) ...[
                const SizedBox(height: AppSpacing.gap8),
                Text(
                  update.reflection!,
                  key: const ValueKey('feed_reflection'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: AppTheme.fontSerif,
                    fontStyle: FontStyle.italic,
                    height: 1.45,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.gap8),
              _AmenPill(
                key: ValueKey('amen_${update.key}'),
                amened: amened,
                count: amenCount,
                onTap: onAmen,
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.hPadding,
        vertical: AppSpacing.gap8,
      ),
      child: isMilestone
          ? Container(
              padding: const EdgeInsets.all(AppSpacing.gap12),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
              ),
              child: body,
            )
          : body,
    );
  }
}

class _StackedAvatars extends StatelessWidget {
  final List<FeedPerson> people;

  const _StackedAvatars({required this.people});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    const step = 14.0;
    final shown = people.take(3).toList();
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              top: AppSpacing.gap6,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: surface, width: 1.5),
                ),
                child: _PersonAvatar(
                  name: shown[i].avatarName,
                  photoUrl: shown[i].photoUrl,
                  size: size - 3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmenPill extends StatelessWidget {
  final bool amened;
  final int count;
  final VoidCallback onTap;

  const _AmenPill({
    super.key,
    required this.amened,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final color = amened ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: amened,
      label: count > 0 ? 'Amen, $count' : 'Amen',
      excludeSemantics: true,
      child: Material(
        color: amened ? colors.primarySoft : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: amened ? colors.primaryLine : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    amened
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: AppSpacing.iconSm,
                    color: color,
                  ),
                  const SizedBox(width: AppSpacing.gap6),
                  Text(
                    'Amen',
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: AppSpacing.gap6),
                    Text(
                      '$count',
                      style:
                          theme.textTheme.labelMedium?.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRowSkeleton extends StatelessWidget {
  const _StatusRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: AppSpacing.horizontal,
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.gap12),
              child: SizedBox(
                width: 60,
                child: Column(
                  children: [
                    Skeleton(width: 56, height: 56, shape: CircleBorder()),
                    SizedBox(height: AppSpacing.gap6),
                    Skeleton(width: 36, height: 10),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.gap16),
          const Skeleton(width: 56, height: 10),
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.gap16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 40, height: 40, shape: CircleBorder()),
                  SizedBox(width: AppSpacing.gap12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 180, height: 14),
                        SizedBox(height: AppSpacing.gap6),
                        Skeleton(width: 110, height: 10),
                        SizedBox(height: AppSpacing.gap8),
                        Skeleton(width: 72, height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The Invite sheet: every way to bring people in, then the reader's Groups,
/// each opening its Group page. [onSelected] closes the sheet and runs the
/// chosen action on the page's context.
class _InviteSheet extends StatelessWidget {
  final List<Group> groups;
  final void Function(void Function(BuildContext pageContext)) onSelected;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GroupService groupService;
  final NudgeService nudgeService;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const _InviteSheet({
    required this.groups,
    required this.onSelected,
    required this.auth,
    required this.firestore,
    required this.groupService,
    required this.nudgeService,
    required this.vibrationService,
    required this.dateProvider,
  });

  void _shareCode(BuildContext context) {
    void open(Group group) {
      vibrationService.lightImpact();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ShareCodePage(
          group: group,
          groupService: groupService,
          vibrationService: vibrationService,
        ),
      ));
    }

    if (groups.length == 1) return open(groups.first);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => _SheetBody(
        title: 'Share which group\'s code?',
        children: [
          for (final group in groups)
            _SheetRow(
              icon: Icons.groups_outlined,
              label: group.name,
              onTap: () {
                Navigator.of(sheetContext).pop();
                open(group);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SheetBody(
      title: 'Bring people in',
      children: [
        if (groups.isNotEmpty)
          _SheetRow(
            icon: Icons.ios_share_rounded,
            label: 'Share a code',
            onTap: () => onSelected(_shareCode),
          ),
        _SheetRow(
          icon: Icons.vpn_key_outlined,
          label: 'Have a code?',
          onTap: () => onSelected((c) => EmptyGroupState.openHaveCode(
                c,
                groupService: groupService,
                auth: auth,
                vibrationService: vibrationService,
              )),
        ),
        _SheetRow(
          icon: Icons.search_rounded,
          label: 'Find a group',
          onTap: () => onSelected((c) => EmptyGroupState.openFindGroup(
                c,
                groupService: groupService,
                auth: auth,
                vibrationService: vibrationService,
              )),
        ),
        _SheetRow(
          icon: Icons.add_rounded,
          label: 'Create a group',
          onTap: () => onSelected((c) => EmptyGroupState.openCreateGroup(
                c,
                firestore: firestore,
                auth: auth,
                groupService: groupService,
                vibrationService: vibrationService,
              )),
        ),
        if (groups.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                0, AppSpacing.gap16, 0, AppSpacing.gap4),
            child: Text(
              'YOUR GROUPS',
              style: AppTextStyles.caption(context).copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
          for (final group in groups)
            _SheetRow(
              icon: Icons.groups_outlined,
              label: group.name,
              detail: '${group.memberCount} '
                  'member${group.memberCount == 1 ? '' : 's'} · '
                  '${GroupPreviewSheet.readingLabel(group)}',
              trailing: true,
              onTap: () => onSelected((c) {
                vibrationService.lightImpact();
                Navigator.of(c).push(MaterialPageRoute(
                  builder: (_) => GroupMembersPage(
                    group: group,
                    groupService: groupService,
                    nudgeService: nudgeService,
                    auth: auth,
                    vibrationService: vibrationService,
                    currentDate: dateProvider(),
                  ),
                ));
              }),
            ),
        ],
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SheetBody({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding, AppSpacing.gap12,
          AppSpacing.hPadding, AppSpacing.gap24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.gap8),
          ...children,
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final bool trailing;
  final VoidCallback onTap;

  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.trailing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rChip),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.iconMd, color: colorScheme.primary),
            const SizedBox(width: AppSpacing.gap12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (detail != null)
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing)
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
