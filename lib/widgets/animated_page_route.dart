import 'package:flutter/material.dart';

/// Creates a [PageRouteBuilder] that applies a combined fade and scale
/// transition to the page.
PageRouteBuilder<T> animatedPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return _scaleFadeTransition(child, animation);
    },
  );
}

/// Builds a fade and scale transition used by [animatedPageRoute] and other
/// widgets needing the same effect.
Widget _scaleFadeTransition(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
      child: child,
    ),
  );
}

/// Public helper to reuse the scale and fade transition in widgets like
/// [AnimatedSwitcher].
Widget scaleFadeTransition(Widget child, Animation<double> animation) =>
    _scaleFadeTransition(child, animation);
