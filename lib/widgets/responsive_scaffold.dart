// Displays a NavigationRail on wide layouts and a NavigationBar on narrow ones
// by switching based on the current width.
import 'package:flutter/material.dart';

/// A scaffold that adapts its navigation UI to the screen width.
///
/// Required parameters are [selectedIndex], [onDestinationSelected], [pages],
/// and [destinations]. The [pages] and [destinations] lists should have the
/// same length so each destination maps to a page.
class ResponsiveScaffold extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final Widget? appBar;
  final Widget? drawer;
  final int? contentIndex;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Widget? offlineBanner;

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
    this.offlineBanner,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant ResponsiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _pageController.jumpToPage(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 600;
    final int safeSelected = widget.destinations.isEmpty
        ? 0
        : widget.selectedIndex.clamp(0, widget.destinations.length - 1);

    return Scaffold(
      key: widget.scaffoldKey,
      appBar: widget.appBar is PreferredSizeWidget
          ? widget.appBar as PreferredSizeWidget
          : null,
      drawer: widget.drawer,
      body: Column(
        children: [
          if (widget.offlineBanner != null) widget.offlineBanner!,
          Expanded(
            child: Row(
              children: [
                if (isWide && widget.destinations.length > 1)
                  NavigationRail(
                    selectedIndex: safeSelected,
                    onDestinationSelected: widget.onDestinationSelected,
                    labelType: NavigationRailLabelType.all,
                    leading: const SizedBox(height: 16),
                    destinations:
                        widget.destinations.asMap().entries.map((entry) {
                      final d = entry.value;
                      return NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon ?? d.icon,
                        label: Text(d.label),
                      );
                    }).toList(),
                  ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics:
                        const NeverScrollableScrollPhysics(), // Disable swipe
                    children: widget.pages,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide || widget.destinations.length <= 1
          ? null
          : NavigationBar(
              selectedIndex: safeSelected,
              onDestinationSelected: widget.onDestinationSelected,
              height: 88,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: widget.destinations.asMap().entries.map((entry) {
                final d = entry.value;
                return NavigationDestination(
                  icon: d.icon,
                  selectedIcon: d.selectedIcon ?? d.icon,
                  label: d.label,
                  tooltip: d.tooltip,
                );
              }).toList(),
            ),
    );
  }
}
