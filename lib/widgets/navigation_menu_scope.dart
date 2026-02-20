import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_role_service.dart';
import '../services/vibration_service.dart';
import 'app_menu_sheet.dart';

/// Provides access to the shared navigation menu so descendants can show it.
class NavigationMenuScope extends InheritedWidget {
  const NavigationMenuScope({
    super.key,
    required super.child,
    required this.onNavigate,
    required this.friendsIndex,
    this.vibrationService = const VibrationService(),
    this.adminRoleService,
    this.auth,
    this.firestore,
  });

  /// Invoked when a menu item is selected.
  final ValueChanged<int> onNavigate;

  /// Index of the friends page within the main navigation stack.
  final int friendsIndex;

  /// Vibration service used when opening or interacting with the menu.
  final VibrationService vibrationService;

  /// Service used to determine whether the current user should see admin items.
  final AdminRoleService? adminRoleService;

  /// Auth instance used for navigation items.
  final FirebaseAuth? auth;

  /// Firestore instance used for navigation items.
  final FirebaseFirestore? firestore;

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
      adminRoleService: adminRoleService,
      auth: auth,
      firestore: firestore,
    );
  }

  @override
  bool updateShouldNotify(NavigationMenuScope oldWidget) {
    return onNavigate != oldWidget.onNavigate ||
        friendsIndex != oldWidget.friendsIndex ||
        vibrationService != oldWidget.vibrationService ||
        adminRoleService != oldWidget.adminRoleService ||
        auth != oldWidget.auth ||
        firestore != oldWidget.firestore;
  }
}
