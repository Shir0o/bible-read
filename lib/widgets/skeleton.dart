import 'package:flutter/material.dart';

/// A basic skeleton widget that displays a shimmering box.
///
/// Used to build complex skeleton screens by composing multiple [Skeleton]s.
class Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;
  final ShapeBorder? shape;
  final Color? color;

  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.shape,
    this.color,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Use onSurface with transparency to ensure visibility on both
    // surface and surfaceContainerHighest backgrounds.
    final baseColor = widget.color ?? colorScheme.onSurface.withValues(alpha: 0.1);
    final highlightColor = colorScheme.onSurface.withValues(alpha: 0.2);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            shape: widget.shape ??
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(
                slidePercent: _animation.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final translation = bounds.width * slidePercent;
    return Matrix4.translationValues(translation, 0, 0);
  }
}
