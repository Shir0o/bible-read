import 'package:flutter/material.dart';

/// Icon button that opens the nearest ancestor application's drawer.
class MenuButton extends StatelessWidget {
  /// Optional key for the surrounding [Scaffold].
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Creates a [MenuButton].
  const MenuButton({super.key, this.scaffoldKey});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () {
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
