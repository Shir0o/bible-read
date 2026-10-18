import 'package:cloud_firestore/cloud_firestore.dart';
import '../common_styles.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../skeleton_loader.dart';
import '../skeletons/list_rows_skeleton.dart';
import '../../models/group.dart';
import '../../pages/create_plan_page.dart';
import '../../pages/join_by_code_page.dart';
import '../../services/group_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';
import '../app_bottom_sheet.dart';
import '../find_group_card.dart';
import '../group_preview_sheet.dart';
import '../nav_glyphs.dart';

/// The empty state for Circle when the reader has no active groups.
///
/// Follows `design/circle-path-second-pass/Main.dc.html`:
/// - Card on surfaceContainerLowest / #FFFDFA with 22px rounded corners and border.
/// - 64x64 circle icon tinted with primary color (10% opacity) containing [CircleGlyph].
/// - "No one here yet" serif title.
/// - "Your Circle is your Friends and everyone you share a group with."
/// - Three clear action paths:
///   1. "Have a code?" -> [JoinByCodePage]
///   2. "Find a group" -> Browse public groups sheet
///   3. "Create a group" -> [CreatePlanPage]
class EmptyGroupState extends StatelessWidget {
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final GroupService? groupService;
  final VibrationService? vibrationService;

  const EmptyGroupState({
    super.key,
    this.auth,
    this.firestore,
    this.groupService,
    this.vibrationService,
  });

  GroupService get _groupService => groupService ?? GroupService();
  FirebaseAuth get _auth => auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore => firestore ?? FirebaseFirestore.instance;
  VibrationService get _vibrationService =>
      vibrationService ?? const VibrationService();

  void _onHaveCode(BuildContext context) => openHaveCode(
        context,
        groupService: _groupService,
        auth: _auth,
        vibrationService: _vibrationService,
      );

  void _onFindGroup(BuildContext context) => openFindGroup(
        context,
        groupService: _groupService,
        auth: _auth,
        vibrationService: _vibrationService,
      );

  void _onCreateGroup(BuildContext context) => openCreateGroup(
        context,
        firestore: _firestore,
        auth: _auth,
        groupService: _groupService,
        vibrationService: _vibrationService,
      );

  /// Opens [JoinByCodePage]. Shared with Circle's Invite sheet.
  static void openHaveCode(
    BuildContext context, {
    required GroupService groupService,
    required FirebaseAuth auth,
    required VibrationService vibrationService,
  }) {
    vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinByCodePage(
          groupService: groupService,
          auth: auth,
          vibrationService: vibrationService,
        ),
      ),
    );
  }

  /// Opens the public-group browse sheet. Shared with Circle's Invite sheet.
  static void openFindGroup(
    BuildContext context, {
    required GroupService groupService,
    required FirebaseAuth auth,
    required VibrationService vibrationService,
  }) {
    vibrationService.lightImpact();
    showAppSheet(
      context: context,
      fullHeight: true,
      builder: (sheetContext) => _FindGroupSheetContent(
        groupService: groupService,
        auth: auth,
        vibrationService: vibrationService,
      ),
    );
  }

  /// Opens [CreatePlanPage] on "With a group". Shared with Circle's Invite
  /// sheet.
  static void openCreateGroup(
    BuildContext context, {
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required GroupService groupService,
    required VibrationService vibrationService,
  }) {
    vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePlanPage(
          firestore: firestore,
          auth: auth,
          vibrationService: vibrationService,
          groupService: groupService,
          initialAudience: PlanAudience.group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: appColors.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gap24, AppSpacing.gap32,
          AppSpacing.gap24, AppSpacing.gap24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: CircleGlyph(
              color: colorScheme.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),
          Text(
            'No one here yet',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.gap8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              'Your Circle is your Friends and everyone you share a group with.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.gap24),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: FilledButton(
              onPressed: () => _onHaveCode(context),
              child: const Text('Have a code?'),
            ),
          ),
          const SizedBox(height: AppSpacing.gap8),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: OutlinedButton(
              onPressed: () => _onFindGroup(context),
              child: const Text('Find a group'),
            ),
          ),
          const SizedBox(height: AppSpacing.gap8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () => _onCreateGroup(context),
              style: AppButtonStyles.mutedText(context),
              child: const Text('Create a group'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindGroupSheetContent extends StatelessWidget {
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const _FindGroupSheetContent({
    required this.groupService,
    required this.auth,
    required this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap20, vertical: AppSpacing.gap12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find a group',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.gap4),
          Text(
            'Join an open group to read together.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.gap16),
          Expanded(
            child: StreamBuilder<List<Group>>(
              stream: groupService.allGroups(),
              builder: (context, snapshot) {
                final waiting =
                    snapshot.connectionState == ConnectionState.waiting;
                return SkeletonLoader(
                  loading: waiting,
                  skeleton: const ListRowsSkeleton(),
                  child: waiting
                      ? const SizedBox.shrink()
                      : _buildGroups(context, snapshot.data ?? []),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroups(BuildContext context, List<Group> allGroups) {
    final colorScheme = Theme.of(context).colorScheme;
    final groups = allGroups.where((g) => g.isPublic).toList();

    if (groups.isEmpty) {
      return Center(
        child: Text(
          'No public groups available at this time.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return FindGroupCard(
          group: group,
          readingSummary: GroupPreviewSheet.readingLabel(group),
          onTap: () {
            vibrationService.lightImpact();
            GroupPreviewSheet.show(
              context: context,
              group: group,
              groupService: groupService,
              auth: auth,
              vibrationService: vibrationService,
            );
          },
        );
      },
    );
  }
}
