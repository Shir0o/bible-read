import 'package:flutter/material.dart';

/// Icon button that opens the application drawer.
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
        final state = scaffoldKey?.currentState ??
            Scaffold.maybeOf(context) ??
            context.findRootAncestorStateOfType<ScaffoldState>();
        state?.openDrawer();
      },
    );
  }
}
