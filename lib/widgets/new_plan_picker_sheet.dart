import 'package:flutter/material.dart';

/// What kind of plan the reader chose to start from the new-plan chooser.
enum NewPlanKind {
  /// A personal plan — just for the reader, at their own pace.
  personal,

  /// A group plan — read through scripture together with a circle.
  group,
}

/// Opens the "Start a new plan" chooser sheet, asking whether the reader wants
/// a personal or a group plan. Resolves to the chosen [NewPlanKind], or `null`
/// if the reader dismissed the sheet without picking.
///
/// Shared by Home's "Start a new plan" button and the All Plans hub's "Enroll
/// in a new plan" button so the two affordances stay visually in sync.
Future<NewPlanKind?> showNewPlanPicker(BuildContext context) {
  return showModalBottomSheet<NewPlanKind>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _NewPlanPickerSheet(),
  );
}

class _NewPlanPickerSheet extends StatelessWidget {
  const _NewPlanPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: colorScheme.shadow.withValues(alpha: 0.16),
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Start a new plan',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Read on your own, or together with a circle',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _ChoiceTile(
                icon: Icons.explore_outlined,
                title: 'Personal plan',
                subtitle: 'Just for you, at your own pace',
                onTap: () => Navigator.of(context).pop(NewPlanKind.personal),
              ),
              const SizedBox(height: 10),
              _ChoiceTile(
                icon: Icons.groups_outlined,
                title: 'Group plan',
                subtitle: 'Read through scripture with friends',
                onTap: () => Navigator.of(context).pop(NewPlanKind.group),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
