import 'package:flutter/material.dart';

class LimitedBouncingScrollPhysics extends BouncingScrollPhysics {
  final double maxHeight;

  const LimitedBouncingScrollPhysics({
    required this.maxHeight,
    super.parent,
  });

  @override
  LimitedBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return LimitedBouncingScrollPhysics(
      maxHeight: maxHeight,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Check if we are overscrolling at the top
    if (value < position.minScrollExtent &&
        value < position.minScrollExtent - maxHeight) {
      // If the new value exceeds the limit, consume the excess
      return value - (position.minScrollExtent - maxHeight);
    }
    
    return super.applyBoundaryConditions(position, value);
  }
}
