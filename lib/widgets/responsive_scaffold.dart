import 'package:flutter/material.dart';

import 'animated_page_route.dart';

class ResponsiveScaffold extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;

  const ResponsiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pages,
    required this.destinations,
  });

  Widget _animatedIcon(Widget icon, bool selected) {
    return AnimatedScale(
      scale: selected ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: icon,
    );
  }

  List<NavigationDestination> _buildAnimatedDestinations() {
    return List<NavigationDestination>.generate(destinations.length, (index) {
      final d = destinations[index];
      final selected = index == selectedIndex;
      return NavigationDestination(
        icon: _animatedIcon(d.icon, selected),
        selectedIcon: _animatedIcon(d.selectedIcon ?? d.icon, selected),
        label: d.label,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 600;
    final animatedDestinations = _buildAnimatedDestinations();
    return Scaffold(
      body: Row(
        children: [
          if (isWide && destinations.length > 1)
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: animatedDestinations
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  scaleFadeTransition(child, animation),
              child: KeyedSubtree(
                key: ValueKey<int>(selectedIndex),
                child: pages[selectedIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide || destinations.length <= 1
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: animatedDestinations,
            ),
    );
  }
}
