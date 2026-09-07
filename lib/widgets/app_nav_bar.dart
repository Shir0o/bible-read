// The bottom navigation bar, drawn in the app's own system (treatment B of
// the navigation redesign): custom stroke glyphs on the theme palette, no
// Material pill indicator, icons alone at rest with only the active
// destination labelled.
//
// Inactive destinations reserve the label's space — the label is laid out and
// painted transparent — so icons hold still when the selection changes.
import 'package:bible_read/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The app's bottom navigation bar.
///
/// Takes the same [NavigationDestination] list as the wide-layout rail so
/// both carry identical names and glyphs.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: colorScheme.outlineVariant),
            Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _AppDestination(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDestination extends StatelessWidget {
  const _AppDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.vPaddingSmall,
            horizontal: AppSpacing.gap4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 24,
                child: selected
                    ? (destination.selectedIcon ?? destination.icon)
                    : destination.icon,
              ),
              SizedBox(height: AppSpacing.gap4),
              // Always laid out and always in the semantics tree; painted
              // invisible when unselected so the icon does not shift when the
              // selection changes.
              Visibility(
                visible: selected,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                maintainSemantics: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    softWrap: false,
                    style: labelStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
