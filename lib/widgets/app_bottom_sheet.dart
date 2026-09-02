import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows a modal sheet with the app's standard chrome.
///
/// Extracted from the hand-rolled containers the existing sheets each repeat:
/// transparent barrier over the app scrim, a rounded top, and a grab handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fullHeight = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: AppColors.of(context).scrim,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppSheetSurface(
      fullHeight: fullHeight,
      child: builder(sheetContext),
    ),
  );
}

/// The sheet body: rounded surface, shadow, and a grab handle.
class AppSheetSurface extends StatelessWidget {
  final Widget child;

  /// Whether the sheet should fill most of the screen, for content that
  /// scrolls (a long chapter grid) rather than a short list of choices.
  final bool fullHeight;

  const AppSheetSurface({
    super.key,
    required this.child,
    this.fullHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final surface = Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.rSheet),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: colorScheme.shadow.withValues(alpha: 0.16),
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.rChip),
                ),
              ),
            ),
            if (fullHeight) Expanded(child: child) else Flexible(child: child),
          ],
        ),
      ),
    );

    if (!fullHeight) return surface;

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: surface,
    );
  }
}
