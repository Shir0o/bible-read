import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/badge_award.dart';
import '../../models/read_through.dart';
import '../../services/badge_service.dart';
import '../../services/read_through_service.dart';
import '../../theme/app_theme.dart';

/// The read-through badges, earned and still to come.
class BadgeStrip extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final BadgeService? badgeService;
  final ReadThroughService? readThroughService;

  const BadgeStrip({
    super.key,
    required this.firestore,
    required this.auth,
    this.badgeService,
    this.readThroughService,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final badges = badgeService ?? BadgeService(firestore: firestore);
    final readThroughs =
        readThroughService ?? ReadThroughService(firestore: firestore);

    return StreamBuilder<List<BadgeAward>>(
      stream: badges.watch(user.uid),
      builder: (context, badgeSnapshot) {
        final held = (badgeSnapshot.data ?? const <BadgeAward>[])
            .map((b) => b.id)
            .toSet();

        return StreamBuilder<List<ReadThrough>>(
          stream: readThroughs.watch(user.uid),
          builder: (context, ledgerSnapshot) {
            final counts = ReadThroughService.countsFrom(
              ledgerSnapshot.data ?? const <ReadThrough>[],
            );
            return _Strip(held: held, counts: counts);
          },
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  final Set<String> held;
  final ReadThroughCounts counts;

  const _Strip({required this.held, required this.counts});

  /// The next badge the reader has not yet earned, for the "still to come"
  /// line under the strip.
  BadgeDefinition? get _next {
    for (final badge in BadgeDefinition.all) {
      if (!held.contains(badge.id)) return badge;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final next = _next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text('Badges', style: textTheme.titleLarge),
        ),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: BadgeDefinition.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final badge = BadgeDefinition.all[index];
              return _Badge(badge: badge, earned: held.contains(badge.id));
            },
          ),
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _NextUp(badge: next, counts: counts),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final BadgeDefinition badge;
  final bool earned;

  const _Badge({required this.badge, required this.earned});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    // The whole-Bible badges wear the app's gold sun; the testaments wear the
    // soft primary.
    final isGold = badge.id == 'first_bible';

    return Semantics(
      label: '${badge.title}, ${earned ? "earned" : "not yet earned"}. '
          '${badge.requirement}',
      excludeSemantics: true,
      child: SizedBox(
        width: 96,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned
                    ? (isGold ? null : appColors.primarySoft)
                    : colorScheme.surfaceContainer,
                gradient: earned && isGold
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFE9A8), Color(0xFFFFC24D)],
                      )
                    : null,
                border: Border.all(
                  color: earned
                      ? (isGold
                          ? const Color(0xFF2A2438)
                          : appColors.primaryLine)
                      : appColors.border,
                  width: earned && isGold ? 2 : 1,
                ),
              ),
              child: Center(
                child: _BadgeGlyph(
                  badge: badge,
                  color: earned
                      ? (isGold ? const Color(0xFF2A2438) : colorScheme.primary)
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                height: 1.3,
                color: earned
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks the mark for a badge: stone tablets for the Old Testament, a fish for
/// the New, the app's book for a whole Bible, a count for the tiers.
class _BadgeGlyph extends StatelessWidget {
  final BadgeDefinition badge;
  final Color color;
  final double size;

  const _BadgeGlyph({
    required this.badge,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    switch (badge.id) {
      case 'first_ot':
        return CustomPaint(
          size: Size(size, size),
          painter: TabletsPainter(color: color),
        );
      case 'first_nt':
        return CustomPaint(
          size: Size(size, size),
          painter: FishPainter(color: color),
        );
      case 'first_bible':
        return Icon(Icons.menu_book_rounded, size: size * 1.07, color: color);
      default:
        final times = badge.id == 'bible_5' ? 5 : 10;
        return Text(
          '×$times',
          style: TextStyle(
            fontFamily: AppTheme.fontSerif,
            fontSize: size * 0.79,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        );
    }
  }
}

/// Two stone tablets — the Old Testament mark.
class TabletsPainter extends CustomPainter {
  final Color color;

  const TabletsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    void tablet(double left) {
      final path = Path()
        ..moveTo(left * scale, 20.5 * scale)
        ..lineTo(left * scale, 8.5 * scale)
        ..arcToPoint(
          Offset((left + 7) * scale, 8.5 * scale),
          radius: Radius.circular(3.5 * scale),
        )
        ..lineTo((left + 7) * scale, 20.5 * scale)
        ..close();
      canvas.drawPath(path, paint);
    }

    tablet(4);
    tablet(13);
  }

  @override
  bool shouldRepaint(TabletsPainter oldDelegate) => oldDelegate.color != color;
}

/// An ichthys — the New Testament mark.
class FishPainter extends CustomPainter {
  final Color color;

  const FishPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(22 * scale, 12 * scale)
      // Upper edge, sweeping back to the tail.
      ..cubicTo(
          17.5 * scale, 8 * scale, 13 * scale, 6 * scale, 9 * scale, 6 * scale)
      // Into the tail notch.
      ..cubicTo(11 * scale, 8.5 * scale, 12 * scale, 10.5 * scale, 12 * scale,
          12 * scale)
      // Back out of it.
      ..cubicTo(12 * scale, 13.5 * scale, 11 * scale, 15.5 * scale, 9 * scale,
          18 * scale)
      // Lower edge, returning to the nose.
      ..cubicTo(13 * scale, 18 * scale, 17.5 * scale, 16 * scale, 22 * scale,
          12 * scale)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(FishPainter oldDelegate) => oldDelegate.color != color;
}

/// One line on what is still ahead.
class _NextUp extends StatelessWidget {
  final BadgeDefinition badge;
  final ReadThroughCounts counts;

  const _NextUp({required this.badge, required this.counts});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remaining = badge.remainingFor(counts);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainer,
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Center(
              child: _BadgeGlyph(
                badge: badge,
                color: colorScheme.onSurfaceVariant,
                size: 19,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remaining <= 1 ? 'One more to go' : '$remaining more to go',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${badge.title} — ${badge.requirement.toLowerCase()}.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
