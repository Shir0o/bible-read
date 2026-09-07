// The navigation glyphs — a small family of stroke icons drawn for this app,
// replacing the Material outline/filled pairs on the bottom bar and rail.
//
// Every glyph is painted on the same 24×24 grid with the same 1.8 stroke
// weight, round caps and joins, so the three read as one family. Colours are
// resolved by the caller from the app theme; nothing here hardcodes palette
// values.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared drawing constants: the logical grid the paths are authored on and
/// the stroke weight every glyph in the family uses.
const double _glyphGrid = 24;
const double _glyphStrokeWidth = 1.8;

/// Base painter: scales the 24-grid geometry to the laid-out size and applies
/// the shared stroke style.
abstract class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color);

  final Color color;

  void draw(Canvas canvas, Paint stroke, Paint fill);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _glyphGrid, size.height / _glyphGrid);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _glyphStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    draw(canvas, stroke, fill);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.color != color;
}

/// A glyph widget renders itself into a [size]-squared box.
mixin _GlyphWidget on StatelessWidget {
  Color get color;
  double get size;
  CustomPainter get painter;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: painter);
}

/// Today — a sun. The reader's daily reading.
class TodayGlyph extends StatelessWidget with _GlyphWidget {
  const TodayGlyph({super.key, required this.color, this.size = 24});

  @override
  final Color color;

  @override
  final double size;

  @override
  CustomPainter get painter => _TodayPainter(color);
}

class _TodayPainter extends _GlyphPainter {
  _TodayPainter(super.color);

  @override
  void draw(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 4.2, stroke);
    final rays = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final sin = math.sin(angle);
      final cos = math.cos(angle);
      rays.moveTo(12 + 7.2 * cos, 12 + 7.2 * sin);
      rays.lineTo(12 + 9.6 * cos, 12 + 9.6 * sin);
    }
    canvas.drawPath(rays, stroke);
  }
}

/// Circle — a ring of three readers. Everyone you share a Group with.
class CircleGlyph extends StatelessWidget with _GlyphWidget {
  const CircleGlyph({super.key, required this.color, this.size = 24});

  @override
  final Color color;

  @override
  final double size;

  @override
  CustomPainter get painter => _CirclePainter(color);
}

class _CirclePainter extends _GlyphPainter {
  _CirclePainter(super.color);

  @override
  void draw(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 7.6, stroke);
    // Three beads seated on the ring at 90°, 210° and 330°.
    canvas.drawCircle(const Offset(12, 4.4), 2.1, fill);
    canvas.drawCircle(const Offset(5.42, 15.8), 2.1, fill);
    canvas.drawCircle(const Offset(18.58, 15.8), 2.1, fill);
  }
}

/// Path — a route from a start point to a destination ring.
class PathGlyph extends StatelessWidget with _GlyphWidget {
  const PathGlyph({super.key, required this.color, this.size = 24});

  @override
  final Color color;

  @override
  final double size;

  @override
  CustomPainter get painter => _PathPainter(color);
}

class _PathPainter extends _GlyphPainter {
  _PathPainter(super.color);

  @override
  void draw(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(5.6, 18.4), 2.0, fill);
    canvas.drawPath(
      Path()
        ..moveTo(7.6, 18.4)
        ..cubicTo(13.6, 18.4, 10.4, 5.6, 16.2, 5.6),
      stroke,
    );
    canvas.drawCircle(const Offset(18.4, 5.6), 2.2, stroke);
  }
}
