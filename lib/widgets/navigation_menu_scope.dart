import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import 'app_menu_sheet.dart';

/// Provides access to the shared navigation menu so descendants can show it.
class NavigationMenuScope extends InheritedWidget {
  const NavigationMenuScope({
    super.key,
    required super.child,
    required this.onNavigate,
    this.vibrationService = const VibrationService(),
  });

  /// Invoked when a menu item is selected.
  final ValueChanged<int> onNavigate;

  /// Vibration service used when opening or interacting with the menu.
  final VibrationService vibrationService;

  /// Retrieves the nearest [NavigationMenuScope] above [context], if any.
  static NavigationMenuScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavigationMenuScope>();
  }

  /// Retrieves the nearest [NavigationMenuScope] above [context].
  static NavigationMenuScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError('NavigationMenuScope not found in widget tree.');
    }
    return scope;
  }

  /// Displays the shared navigation menu using a modal bottom sheet.
  Future<void> showMenu(BuildContext context) {
    return AppMenuSheet.show(
      context: context,
      onNavigate: onNavigate,
      vibrationService: vibrationService,
    );
  }

  @override
  bool updateShouldNotify(NavigationMenuScope oldWidget) {
    return onNavigate != oldWidget.onNavigate ||
        vibrationService != oldWidget.vibrationService;
  }
}
