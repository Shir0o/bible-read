import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_plan_config.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/group_plan_form.dart';
import '../widgets/group_plan_keys.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/sub_header.dart';
import 'adjust_days_page.dart';
import 'group_detail_page.dart';

class CreateGroupPage extends StatefulWidget {
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  CreateGroupPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _nameController = TextEditingController();
  late GroupPlanDraft _draft = GroupPlanDraft.initial();
  GeneratedPlan _plan = GeneratedPlan.empty;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// A name derived from the books, used until the reader types their own.
  String get _suggestedName {
    final books = _draft.books;
    if (books.isEmpty) return 'Reading Plan';
    if (books.length <= 2) return '${books.join(', ')} Plan';
    return '${books.take(2).join(', ')} & more Plan';
  }

  String? get _validationMessage {
    if (_draft.books.isEmpty) return 'Add at least one book to read.';
    if (_plan.days.isEmpty) {
      return 'Choose an end date to work out the pace.';
    }
    return null;
  }

  Future<void> _createPlan() async {
    final user = widget.auth.currentUser;
    if (user == null || _validationMessage != null) return;

    unawaited(widget.vibrationService.mediumImpact());
    setState(() => _isCreating = true);

    final name = _nameController.text.trim().isEmpty
        ? _suggestedName
        : _nameController.text.trim();

    try {
      final groupId = await widget.groupService.createGroup(
        ownerUid: user.uid,
        name: name,
      );

      await widget.groupService.updateScheduleBatch(
        groupId: groupId,
        schedules: _plan.days,
      );

      await widget.groupService.updatePlanConfig(
        groupId: groupId,
        config: _draft,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GroupDetailPage(
            group: Group(
              id: groupId,
              name: name,
              ownerUid: user.uid,
              memberCount: 1,
            ),
            groupService: widget.groupService,
            auth: widget.auth,
          ),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the plan.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final validation = _validationMessage;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'New group plan',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.hPadding,
                  6,
                  AppSpacing.hPadding,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Name', style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.gap8),
                    TextField(
                      key: GroupPlanKeys.nameField,
                      controller: _nameController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: _suggestedName),
                    ),
                    const SizedBox(height: AppSpacing.gap24),
                    GroupPlanForm(
                      initial: _draft,
                      vibrationService: widget.vibrationService,
                      onSeeAllDays: _openAdjustDays,
                      onChanged: (draft, plan) {
                        setState(() {
                          _draft = draft;
                          _plan = plan;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(top: BorderSide(color: appColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.hPadding,
                12,
                AppSpacing.hPadding,
                20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (validation != null) ...[
                    Text(
                      validation,
                      key: GroupPlanKeys.validationMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.gap8),
                  ],
                  FilledButton(
                    key: GroupPlanKeys.submitButton,
                    onPressed: (_isCreating || validation != null)
                        ? null
                        : _createPlan,
                    child: _isCreating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create plan'),
                  ),
                  if (validation == null && _plan.days.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      '${_plan.totalChapters} chapters · '
                      '${_plan.days.length} days · ends '
                      '${formatPlanDateShort(_plan.finishesOn!)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<GroupPlanDraft?> _openAdjustDays(GroupPlanDraft draft) {
    return Navigator.push<GroupPlanDraft>(
      context,
      MaterialPageRoute(
        builder: (context) => AdjustDaysPage(
          draft: draft,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }
}
