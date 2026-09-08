import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/circle_member.dart';
import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/catch_up_engine.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/nudge_service.dart';
import '../services/read_log_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import 'group_detail_page.dart';
import '../widgets/app_header.dart';
import '../widgets/community/empty_group_state.dart';
import '../widgets/nudge_sheet.dart';

/// The Circle tab (ADR-0003): everyone the reader shares a Group with,
/// people-first. One flat, deduplicated list — each row shows today's
/// Showing-up mark and what the person read against their Plan. Groups sit
/// above as filter chips and beneath as a section. The feed data is the
/// per-Group fan-out from ADR-0004; entries deduplicate by person, never by
/// Group.
class CommunityPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GroupService groupService;
  final ReadingStatusService readingStatusService;
  final VibrationService vibrationService;
  final NudgeService? nudgeService;

  final DateTime Function() dateProvider;

  const CommunityPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.groupService,
    required this.readingStatusService,
    required this.vibrationService,
    this.nudgeService,
    required this.dateProvider,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with AutomaticKeepAliveClientMixin {
  /// The Group the filter chips narrow to, or null for the whole Circle.
  String? _filterGroupId;

  /// Page-level Nudge service; injected one wins for tests.
  NudgeService get _nudgeService =>
      widget.nudgeService ?? NudgeService(firestore: widget.firestore);

  @override
  bool get wantKeepAlive => true;

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
          stream: widget.groupService.groupsForUser(user.uid),
          builder: (context, groupsSnap) {
            final groups = groupsSnap.data ?? const <Group>[];
            if (_filterGroupId != null &&
                !groups.any((g) => g.id == _filterGroupId)) {
              _filterGroupId = null;
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: AppHeader(
                    auth: widget.auth,
                    firestore: widget.firestore,
                    vibrationService: widget.vibrationService,
                    dateProvider: widget.dateProvider,
                    eyebrow: groups.isNotEmpty
                        ? _filterGroupId != null
                            ? groups
                                .firstWhere((g) => g.id == _filterGroupId)
                                .name
                            : 'Together'
                        : 'Together',
                    title: 'Community',
                    showProfileIcon: false,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                if (groups.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: EmptyGroupState(),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: _GroupFilterChips(
                      groups: groups,
                      selectedId: _filterGroupId,
                      onSelected: (id) =>
                          setState(() => _filterGroupId = id),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: _CirclePeopleList(
                      auth: widget.auth,
                      groupService: widget.groupService,
                      readingStatusService: widget.readingStatusService,
                      nudgeService: _nudgeService,
                      dateProvider: widget.dateProvider,
                      groupIds: _filterGroupId != null
                          ? [_filterGroupId!]
                          : groups.map((g) => g.id).toList(),
                      myUid: user.uid,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverToBoxAdapter(
                    child: _buildGroupsSection(context, groups),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Groups as the secondary section — people come first. Tapping opens the
  /// Group's detail page, the home of its schedule and actions.
  Widget _buildGroupsSection(BuildContext context, List<Group> groups) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'Your groups',
              style: AppTextStyles.title(context).copyWith(fontSize: 19),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GroupTile(
                group: group,
                onTap: () {
                  widget.vibrationService.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailPage(
                        group: group,
                        groupService: widget.groupService,
                        auth: widget.auth,
                        vibrationService: widget.vibrationService,
                      ),
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: 4, child: Container()),
        ],
      ),
    );
  }
}

/// "Everyone" chip plus one chip per Group; selecting narrows the Circle
/// list to that Group's co-members.
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
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Everyone'),
              selected: selectedId == null,
              showCheckmark: false,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(group.name),
                selected: selectedId == group.id,
                showCheckmark: false,
                onSelected: (_) => onSelected(group.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// The flat Circle list: the reader's own row first, then co-members
/// deduplicated by uid. Ordering is deliberate, never alphabetical —
/// people who have not shown up lead (they are who a nudge reaches),
/// then people who just read (freshest mark first).
class _CirclePeopleList extends StatelessWidget {
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingStatusService readingStatusService;
  final NudgeService nudgeService;
  final DateTime Function() dateProvider;
  final List<String> groupIds;
  final String myUid;

  const _CirclePeopleList({
    required this.auth,
    required this.groupService,
    required this.readingStatusService,
    required this.nudgeService,
    required this.dateProvider,
    required this.groupIds,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<CircleMember>>(
      stream: groupService.circleMembers(myUid),
      builder: (context, circleSnap) {
        final circle = (circleSnap.data ?? const <CircleMember>[])
            .where((m) => m.groupIds.any(groupIds.contains))
            .toList();

        final members = <_PersonStatus>[
          _PersonStatus(uid: myUid, name: null, isMe: true),
          for (final m in circle)
            _PersonStatus(uid: m.uid, name: m.name, isMe: false),
        ]..sort(_PersonStatus.ordering(myUid));

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: AppColors.of(context).border),
                _CirclePersonRow(
                  key: ValueKey(members[i].uid),
                  person: members[i],
                  auth: auth,
                  groupService: groupService,
                  readingStatusService: readingStatusService,
                  dateProvider: dateProvider,
                  groupIds: groupIds,
                  myUid: myUid,
                  nudgeService: nudgeService,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Ordering: not shown up first (nudgeable), then shown up. Within each
/// band: the reader's own row, then freshest mark first. Never alphabetical.
class _PersonStatus {
  final String uid;
  final String? name;
  final bool isMe;

  /// Written by the row once its live status resolves.
  bool showedUp = false;
  DateTime? markedAt;

  _PersonStatus({
    required this.uid,
    required this.name,
    required this.isMe,
  });

  static Comparator<_PersonStatus> ordering(String myUid) => (a, b) {
        if (a.uid == myUid) return -1;
        if (b.uid == myUid) return 1;
        final byShown = (a.showedUp ? 1 : 0).compareTo(b.showedUp ? 1 : 0);
        if (byShown != 0) return byShown;
        return (b.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      };
}

/// One person's row. Each fact streams independently and the row renders
/// complete with any of them absent: the Showing-up mark (from the per-Group
/// feed, ADR-0004), what they read and whether they are behind (from the
/// Group schedule + their progress). No Reflection and no achievement exist
/// yet (#807 / #806 are later) — the row never waits on them.
class _CirclePersonRow extends StatefulWidget {
  final _PersonStatus person;
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingStatusService readingStatusService;
  final DateTime Function() dateProvider;
  final List<String> groupIds;
  final String myUid;
  final NudgeService nudgeService;

  const _CirclePersonRow({
    super.key,
    required this.person,
    required this.auth,
    required this.groupService,
    required this.readingStatusService,
    required this.dateProvider,
    required this.groupIds,
    required this.myUid,
    required this.nudgeService,
  });

  @override
  State<_CirclePersonRow> createState() => _CirclePersonRowState();
}

class _CirclePersonRowState extends State<_CirclePersonRow> {
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
      _feedSub;

  @override
  void initState() {
    super.initState();
    _subscribeFeed();
  }

  @override
  void didUpdateWidget(covariant _CirclePersonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.uid != widget.person.uid) {
      _feedSub?.cancel();
      _subscribeFeed();
    }
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    super.dispose();
  }

  /// Live Showing-up mark for this person from the reader's Groups' feed
  /// entries (ADR-0004). The stream is merged across the reader's Groups by
  /// the service, so a co-member's mark arrives without a refresh.
  void _subscribeFeed() {
    final dateKey = ReadLogService.dateKeyFor(widget.dateProvider());
    final service = ReadLogService(firestore: widget.groupService.firestore);
    _feedSub = service
        .entryDocsForGroups(widget.groupIds, dateKey: dateKey)
        .listen((docs) {
      if (!mounted) return;
      final doc = docs.where((d) => d.id == widget.person.uid).firstOrNull;
      setState(() {
        widget.person
          ..showedUp = doc != null
          ..markedAt = doc != null
              ? (doc.data()['timestamp'] as Timestamp?)?.toDate()
              : null;
      });
    }, onError: (e, st) {
      unawaited(ErrorLogger.log(e, st));
    });
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final isMe = person.uid == widget.myUid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      child: Row(
        children: [
          StreamBuilder<List<GroupSchedule>>(
            stream: widget.groupIds.length == 1
                ? widget.groupService.schedule(widget.groupIds.first)
                : const Stream.empty(),
            builder: (context, scheduleSnap) {
              return StreamBuilder<Set<String>>(
                stream: widget.groupIds.length == 1
                    ? widget.groupService.memberCompletedDates(
                        widget.groupIds.first, person.uid)
                    : const Stream.empty(),
                builder: (context, completedSnap) {
                  final status = widget.groupIds.length == 1
                      ? CatchUpEngine.forGroupSchedule(
                          scheduleSnap.data ?? const <GroupSchedule>[],
                          completedSnap.data ?? const <String>{},
                          today: widget.dateProvider(),
                        )
                      : null;
                  return _RowContent(
                    person: person,
                    isMe: isMe,
                    status: status,
                    completedDateKeys: completedSnap.data ?? const <String>{},
                    statusDate: widget.dateProvider(),
                    nudgeService: widget.nudgeService,
                    myUid: widget.myUid,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Name, status line and optional Nudge chip for one row.
class _RowContent extends StatelessWidget {
  final _PersonStatus person;
  final bool isMe;
  final CatchUpStatus? status;
  final Set<String> completedDateKeys;
  final DateTime statusDate;
  final NudgeService nudgeService;
  final String myUid;

  const _RowContent({
    required this.person,
    required this.isMe,
    required this.status,
    required this.completedDateKeys,
    required this.statusDate,
    required this.nudgeService,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final showedUp = person.showedUp;

    // What they read: only a completed Plan reading names a reference —
    // today's scheduled chapters, done. The bare Showing-up mark names
    // nothing: presence, not performance. A reader who showed up while
    // behind shows both facts in one line; neither collapses into the
    // other.
    final behind = status?.behindCount ?? 0;
    final todayKey = GroupService.dateId(statusDate);
    final readTodayOnPlan =
        status != null && completedDateKeys.contains(todayKey);
    final current = status?.currentReadings ?? const <String>[];
    final reference = readTodayOnPlan && current.isNotEmpty
        ? current.first
        : null;
    final String reading;
    if (!showedUp) {
      reading = _CirclePersonRowStatics._notYet;
    } else if (behind > 0) {
      reading = 'Showed up'
          ' · $behind reading${behind == 1 ? '' : 's'} behind';
    } else if (reference != null) {
      reading = reference;
    } else {
      reading = _CirclePersonRowStatics._showedUp;
    }

    return Expanded(
      child: Row(
        children: [
          _PersonAvatar(name: person.name, photoUrl: null, read: showedUp),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'You' : (person.name ?? 'Member'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  reading,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: showedUp
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isMe && !showedUp)
            _NudgeChip(
              onTap: () async {
                await showNudgeSheet(
                  context,
                  person: NudgePerson(name: person.name ?? 'Reader'),
                  onSend: (message) =>
                      nudgeService.nudgeMember(
                        currentUid: myUid,
                        memberUid: person.uid,
                        currentName: 'You',
                      ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CirclePersonRowStatics {
  static const String _showedUp = 'Showed up';
  static const String _notYet = 'Not yet today';
}

class _PersonAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;
  final bool read;

  const _PersonAvatar({
    required this.name,
    required this.photoUrl,
    required this.read,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = (name?.isNotEmpty ?? false) ? name![0] : '?';
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: read ? colorScheme.primary : colorScheme.outlineVariant,
          width: read ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: photoUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                errorWidget: (context, url, error) =>
                    Icon(Icons.person, color: colorScheme.onSurfaceVariant),
              ),
            )
          : Text(
              initial,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
    );
  }
}

class _NudgeChip extends StatelessWidget {
  final VoidCallback onTap;

  const _NudgeChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: true,
      label: 'Nudge',
      child: InkWell(
        onTap: () {
          const VibrationService().lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'Nudge',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

/// One Group in the section beneath the people list.
class _GroupTile extends StatelessWidget {
  final Group group;
  final VoidCallback onTap;

  const _GroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.groups_outlined,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}