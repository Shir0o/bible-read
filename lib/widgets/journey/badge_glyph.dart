import 'package:flutter/material.dart';

import '../../models/badge_award.dart';
import '../../models/read_through.dart';
import '../../theme/app_theme.dart';

/// The next badge the reader has not yet earned. Only read-through landmarks
/// count here, since their progress is the one the ledger can speak to.
BadgeDefinition? nextBadge(Set<String> held, ReadThroughCounts counts) {
  for (final badge in BadgeDefinition.all) {
    if (held.contains(badge.id)) continue;
    if (badge.remainingFor(counts) == null) continue;
    return badge;
  }
  return null;
}

/// Picks the mark for a badge: stone tablets for the Old Testament, a fish for
/// the New, the app's book for a whole Bible, a count for the tiers.
class BadgeGlyph extends StatelessWidget {
  final BadgeDefinition badge;
  final Color color;
  final double size;

  const BadgeGlyph({
    super.key,
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
      case 'first_book':
        return Icon(Icons.auto_stories_rounded, size: size, color: color);
      case 'plan_finished':
        return Icon(Icons.flag_rounded, size: size, color: color);
      default:
        if (badge.id.startsWith('days_')) {
          // A day count, set in the same serif as the whole-Bible tiers.
          return Text(
            badge.id.substring('days_'.length),
            style: TextStyle(
              fontFamily: AppTheme.fontSerif,
              fontSize: size * 0.79,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          );
        }
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
          radius: Radius.circular(
              3.5 * scale), // token-exempt: icon geometry scaled with the glyph
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
