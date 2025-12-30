// Displays a NavigationRail on wide layouts and a NavigationBar on narrow ones
// by switching based on the current width.
import 'package:flutter/material.dart';

import '../services/vibration_service.dart';

/// A scaffold that adapts its navigation UI to the screen width.
///
/// Required parameters are [selectedIndex], [onDestinationSelected], [pages],
/// and [destinations]. The [pages] and [destinations] lists should have the
/// same length so each destination maps to a page.
class ResponsiveScaffold extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final int? contentIndex;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const ResponsiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pages,
    required this.destinations,
    this.appBar,
    this.drawer,
    this.contentIndex,
    this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 600;
    final int displayIndex = contentIndex ?? selectedIndex;
    final int safeDisplay =
        pages.isEmpty ? 0 : displayIndex.clamp(0, pages.length - 1);
    final int safeSelected = destinations.isEmpty
        ? 0
        : selectedIndex.clamp(0, destinations.length - 1);
    
    return Scaffold(
      key: scaffoldKey,
      appBar: appBar,
      drawer: drawer,
      body: Row(
        children: [
          if (isWide && destinations.length > 1)
            NavigationRail(
              selectedIndex: safeSelected,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: const SizedBox(height: 16),
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon ?? d.icon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: IndexedStack(index: safeDisplay, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: isWide || destinations.length <= 1
          ? null
          : NavigationBar(
              selectedIndex: safeSelected,
              onDestinationSelected: onDestinationSelected,
              height: 88,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: destinations,
            ),
    );
  }
}
