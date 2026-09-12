import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../pages/create_plan_page.dart';
import '../../pages/join_by_code_page.dart';
import '../../services/group_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';
import '../app_bottom_sheet.dart';
import '../common_styles.dart';
import '../find_group_card.dart';
import '../group_preview_sheet.dart';
import '../nav_glyphs.dart';

/// The empty state for Circle when the reader has no active groups.
///
/// Follows `design/circle-path-second-pass/Main.dc.html`:
/// - Card on surfaceContainerLowest / #FFFDFA with 22px rounded corners and border.
/// - 64x64 circle icon tinted with primary color (10% opacity) containing [CircleGlyph].
/// - "No one here yet" serif title.
/// - "Your Circle is everyone you share a group with." descriptive text.
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

  void _onHaveCode(BuildContext context) {
    _vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinByCodePage(
          groupService: _groupService,
          auth: _auth,
          vibrationService: _vibrationService,
        ),
      ),
    );
  }

  void _onFindGroup(BuildContext context) {
    _vibrationService.lightImpact();
    showAppSheet(
      context: context,
      fullHeight: true,
      builder: (sheetContext) => _FindGroupSheetContent(
        groupService: _groupService,
        auth: _auth,
        vibrationService: _vibrationService,
      ),
    );
  }

  void _onCreateGroup(BuildContext context) {
    _vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePlanPage(
          firestore: _firestore,
          auth: _auth,
          vibrationService: _vibrationService,
          groupService: _groupService,
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
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
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
          const SizedBox(height: 18),
          Text(
            'No one here yet',
            style: AppTextStyles.title(context).copyWith(
              fontFamily: AppTheme.fontSerif,
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.25,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              'Your Circle is everyone you share a group with.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.45,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: FilledButton(
              onPressed: () => _onHaveCode(context),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rButton),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Have a code?'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: OutlinedButton(
              onPressed: () => _onFindGroup(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary,
                side: BorderSide(color: appColors.primaryLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rButton),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Find a group'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () => _onCreateGroup(context),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rButton),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find a group',
            style: AppTextStyles.title(context).copyWith(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Join an open group to read together.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Group>>(
              stream: groupService.allGroups(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final groups =
                    (snapshot.data ?? []).where((g) => g.isPublic).toList();

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
              },
            ),
          ),
        ],
      ),
    );
  }
}
