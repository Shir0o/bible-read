import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import 'navigation_menu_scope.dart';

/// Icon button that opens the shared navigation menu.
class MenuButton extends StatelessWidget {
  /// Optional key for the surrounding [Scaffold].
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [MenuButton].
  const MenuButton({
    super.key,
    this.scaffoldKey,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_horiz),
      onPressed: () {
        unawaited(vibrationService.lightImpact());
        final scope = NavigationMenuScope.maybeOf(context);
        if (scope != null) {
          scope.showMenu(context);
          return;
        }

        ScaffoldState? state =
            scaffoldKey?.currentState ?? Scaffold.maybeOf(context);
        BuildContext? ctx = state?.context ?? context;

        while (state != null && !state.hasDrawer) {
          ctx = state.context;
          state = ctx.findAncestorStateOfType<ScaffoldState>();
        }

        state?.openDrawer();
      },
    );
  }
}
