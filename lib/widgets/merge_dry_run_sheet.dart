import 'dart:async';

import 'package:flutter/material.dart';

import '../models/reading_plan_progress.dart';
import '../services/account_linking_service.dart';
import '../services/error_logger.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';

/// Shows the Sanctuary Liturgy merge dry-run bottom sheet.
Future<bool?> showMergeDryRunSheet({
  required BuildContext context,
  required MergeDryRunData dryRunData,
  AccountLinkingService? accountLinkingService,
  Future<void> Function(List<UserPlanProgress> selectedPlans)? onMerge,
  Future<void> Function()? onKeepAccountOnly,
  VibrationService? vibrationService,
}) {
  return showAppSheet<bool>(
    context: context,
    fullHeight: true,
    builder: (sheetContext) => MergeDryRunSheet(
      dryRunData: dryRunData,
      accountLinkingService: accountLinkingService,
      onMerge: onMerge,
      onKeepAccountOnly: onKeepAccountOnly,
      vibrationService: vibrationService ?? const VibrationService(),
    ),
  );
}

/// Sanctuary Liturgy modal bottom sheet displaying a dry-run preview of merged
/// reading days, recomputed habit streaks, and active reading plans.
class MergeDryRunSheet extends StatefulWidget {
  final MergeDryRunData dryRunData;
  final AccountLinkingService? accountLinkingService;
  final Future<void> Function(List<UserPlanProgress> selectedPlans)? onMerge;
  final Future<void> Function()? onKeepAccountOnly;
  final VibrationService vibrationService;

  const MergeDryRunSheet({
    super.key,
    required this.dryRunData,
    this.accountLinkingService,
    this.onMerge,
    this.onKeepAccountOnly,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<MergeDryRunSheet> createState() => _MergeDryRunSheetState();
}

class _MergeDryRunSheetState extends State<MergeDryRunSheet> {
  late final Set<String> _selectedPlanIds;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlanIds =
        widget.dryRunData.mergedPlans.map((p) => p.planId).toSet();
  }

  Future<void> _handleMerge() async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);
    unawaited(widget.vibrationService.lightImpact());

    final selectedPlans = widget.dryRunData.mergedPlans
        .where((p) => _selectedPlanIds.contains(p.planId))
        .toList();

    try {
      if (widget.accountLinkingService != null &&
          widget.dryRunData.targetUid != null) {
        await widget.accountLinkingService!.commitMerge(
          targetUid: widget.dryRunData.targetUid!,
          dates: widget.dryRunData.mergedDates,
          plans: selectedPlans,
        );
      }
      if (widget.onMerge != null) {
        await widget.onMerge!(selectedPlans);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to merge accounts. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  Future<void> _handleKeepAccountOnly() async {
    if (_isCommitting) return;
    unawaited(widget.vibrationService.lightImpact());

    try {
      if (widget.onKeepAccountOnly != null) {
        await widget.onKeepAccountOnly!();
      }
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  Widget _buildStatBox({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    bool isHighlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gap12,
        vertical: AppSpacing.gap8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: AppSpacing.iconSm,
                color: isHighlight
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.gap6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap4),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: AppTheme.fontSerif,
              fontWeight: FontWeight.w700,
              color: isHighlight ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dryRun = widget.dryRunData;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        AppSpacing.gap8,
        AppSpacing.hPadding,
        AppSpacing.gap24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sanctuary Liturgy headline
          Text(
            'Merge reading history',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: AppTheme.fontSerif,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.gap6),
          Text(
            'An existing account was found. Preview how your reading history will be combined before continuing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),

          // Comparison Card
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.rCard),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gap8,
              vertical: AppSpacing.gap12,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        context: context,
                        label: 'Guest Days',
                        value: '${dryRun.guestDays}',
                        icon: Icons.person_outline,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 44,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    Expanded(
                      child: _buildStatBox(
                        context: context,
                        label: 'Account Days',
                        value: '${dryRun.cloudDays}',
                        icon: Icons.cloud_outlined,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.gap8),
                  child: Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        context: context,
                        label: 'Merged Total Days',
                        value: '${dryRun.mergedTotalDays}',
                        icon: Icons.calendar_today_outlined,
                        isHighlight: true,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 44,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    Expanded(
                      child: _buildStatBox(
                        context: context,
                        label: 'Merged Current Streak',
                        value: '${dryRun.mergedStreak}',
                        icon: Icons.local_fire_department_outlined,
                        isHighlight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Checkbox list of active plans to keep
          if (dryRun.mergedPlans.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.gap24),
            Text(
              'Active reading plans to keep',
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: AppTheme.fontSerif,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.gap8),
            Material(
              color: colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: dryRun.mergedPlans.asMap().entries.map((entry) {
                  final index = entry.key;
                  final plan = entry.value;
                  final isSelected = _selectedPlanIds.contains(plan.planId);
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: AppSpacing.hPadding,
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      CheckboxListTile(
                        value: isSelected,
                        onChanged: _isCommitting
                            ? null
                            : (bool? checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedPlanIds.add(plan.planId);
                                  } else {
                                    _selectedPlanIds.remove(plan.planId);
                                  }
                                });
                              },
                        title: Text(
                          plan.planId,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${plan.completedDays.length} days completed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.gap12,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.gap24),

          // Actions
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: FilledButton(
              onPressed: _isCommitting ? null : _handleMerge,
              child: _isCommitting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        // token-exempt: button submitting
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Merge & Continue'),
            ),
          ),
          const SizedBox(height: AppSpacing.gap12),
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: OutlinedButton(
              onPressed: _isCommitting ? null : _handleKeepAccountOnly,
              child: const Text('Keep Account Only'),
            ),
          ),
        ],
      ),
    );
  }
}
