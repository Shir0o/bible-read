import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/join_code_keys.dart';

/// Shows the group's join code so any member can share it, and offers
/// regeneration for a code that has been shared too widely.
class ShareCodePage extends StatefulWidget {
  /// The group whose code is shared.
  final Group group;

  /// Service used to read and rotate the code.
  final GroupService groupService;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Creates a [ShareCodePage].
  const ShareCodePage({
    super.key,
    required this.group,
    required this.groupService,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<ShareCodePage> createState() => _ShareCodePageState();
}

class _ShareCodePageState extends State<ShareCodePage> {
  String? _code;
  String? _error;
  bool _loading = true;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await widget.groupService.joinCodeService
          .ensureGroupCode(widget.group.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the code. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null) return;
    unawaited(widget.vibrationService.lightImpact());
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied')),
    );
  }

  Future<void> _regenerate() async {
    unawaited(widget.vibrationService.lightImpact());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regenerate code?'),
        content: const Text(
          'The current code will stop working. Anyone who has it will no '
          'longer be able to use it to join.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _regenerating = true);
    try {
      final code =
          await widget.groupService.joinCodeService.regenerate(widget.group.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _regenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New code generated — the old one no longer works'),
        ),
      );
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _regenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not generate a new code. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: CommonStyles.buildAppBar(context, 'Share code'),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: SafeArea(
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading || _regenerating) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: AppTextStyles.body(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadCode,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final code = _code!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CommonStyles.buildCard(
          context: context,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                Text(
                  'GROUP JOIN CODE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  code,
                  key: JoinCodeKeys.codeText,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'People can enter this code to join ${widget.group.name}.',
                  style: AppTextStyles.bodySmall(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!widget.group.isPublic) ...[
                  const SizedBox(height: 8),
                  Text(
                    "You'll approve their request before they're in.",
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: JoinCodeKeys.copyButton,
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy code'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: JoinCodeKeys.regenerateButton,
          onPressed: _regenerate,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Regenerate code'),
        ),
        const SizedBox(height: 8),
        Text(
          'The old code stops working.',
          style: AppTextStyles.caption(context).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
