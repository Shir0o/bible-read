import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/error_logger.dart';
import '../services/friend_invite.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_code_keys.dart';
import '../widgets/friend_qr_code.dart';
import '../widgets/qr_scan_view.dart';
import '../widgets/skeleton.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/sub_header.dart';
import 'join_by_code_page.dart';

/// "Add a friend" share side (ADR-0012 V4): the reader's one friend code shown
/// three ways — a QR to scan, the code to type, and a link to send — with Copy,
/// Share link and a single Reset that retires all three. The combined add side
/// ("Their code") is one tap away at the foot of the screen.
class FriendCodePage extends StatefulWidget {
  /// Auth used to identify the code's owner.
  final FirebaseAuth auth;

  /// Friend code operations.
  final FriendService friendService;

  /// Group service, for the add side.
  final GroupService groupService;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Camera scanner for the add side. Defaults to the real camera; tests
  /// inject a fake so no camera is needed.
  final QrScanViewBuilder? scanViewBuilder;

  FriendCodePage({
    super.key,
    FirebaseAuth? auth,
    FriendService? friendService,
    GroupService? groupService,
    VibrationService? vibrationService,
    this.scanViewBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        friendService = friendService ?? FriendService(),
        groupService = groupService ?? GroupService(),
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<FriendCodePage> createState() => _FriendCodePageState();
}

class _FriendCodePageState extends State<FriendCodePage> {
  String? _code;
  String? _error;
  bool _loading = true;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await widget.friendService.ensureMyCode(uid);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your code. Check your connection.';
        _loading = false;
      });
    }
  }

  String _spacedCode(String code) {
    if (code.length <= 4) return code;
    return '${code.substring(0, 4)} ${code.substring(4)}';
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

  Future<void> _shareCode() async {
    final code = _code;
    if (code == null) return;
    unawaited(widget.vibrationService.lightImpact());
    final rawName = widget.auth.currentUser?.displayName?.trim();
    final name = (rawName == null || rawName.isEmpty) ? null : rawName;
    final link = FriendInvite.linkFor(code);
    await SharePlus.instance.share(ShareParams(
      text: name == null
          ? 'Read with me on Bible Reading Challenge: $link'
          : 'Read with me — $name on Bible Reading Challenge: $link',
    ));
  }

  Future<void> _resetCode() async {
    unawaited(widget.vibrationService.lightImpact());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset your code?'),
        content: const Text(
          'The current code, QR and link will stop working. Anyone you are '
          'already friends with stays your friend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    setState(() => _resetting = true);
    try {
      final code = await widget.friendService.resetMyCode(uid);
      if (!mounted) return;
      setState(() {
        _code = code;
        _resetting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New code generated — the old one no longer works'),
        ),
      );
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reset your code. Try again.'),
        ),
      );
    }
  }

  void _openAddSide() {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinByCodePage(
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          friendService: widget.friendService,
          title: 'Their code',
          scanViewBuilder: widget.scanViewBuilder ?? cameraQrScanView,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Add a friend',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Container(
                decoration: CommonStyles.backgroundDecoration(colorScheme),
                child: SafeArea(
                  child: SkeletonLoader(
                    loading: _loading,
                    skeleton: const _FriendCodeSkeleton(),
                    child: _loading
                        ? const SizedBox.shrink()
                        : _buildLoadedBody(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            const SizedBox(height: AppSpacing.gap12),
            TextButton(onPressed: _loadCode, child: const Text('Try again')),
          ],
        ),
      );
    }

    final code = _code;
    if (code == null) {
      return const Center(child: Text('Please sign in'));
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      children: [
        CommonStyles.buildCard(
          context: context,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.gap8),
            child: Column(
              children: [
                FriendQrCode(data: code, key: FriendCodeKeys.qrCode),
                const SizedBox(height: AppSpacing.gap20),
                Text(
                  _spacedCode(code),
                  key: FriendCodeKeys.codeText,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 7,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.gap16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: FriendCodeKeys.copyButton,
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
            ),
            const SizedBox(width: AppSpacing.gap8),
            Expanded(
              child: OutlinedButton.icon(
                key: FriendCodeKeys.shareButton,
                onPressed: _shareCode,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share link'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.gap12),
        Text(
          'Anyone with this code can add you. One code, three ways: they '
          'scan it, type it, or tap the link.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        Row(
          children: [
            TextButton(
              key: FriendCodeKeys.resetButton,
              onPressed: _resetting ? null : _resetCode,
              style: TextButton.styleFrom(
                // token-exempt: compact inline reset action
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _resetting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        // token-exempt: inline button progress
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Reset'),
            ),
            Text(
              'retires all three.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.gap24),
        CommonStyles.buildCard(
          context: context,
          child: InkWell(
            key: FriendCodeKeys.enterCodeButton,
            onTap: _openAddSide,
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gap16),
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.gap12),
                  Expanded(
                    child: Text(
                      'Scan or enter their code',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FriendCodeSkeleton extends StatelessWidget {
  const _FriendCodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.gap16),
      children: [
        CommonStyles.buildCard(
          context: context,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.gap8),
            child: Column(
              children: [
                Skeleton(width: 200, height: 200),
                SizedBox(height: AppSpacing.gap20),
                Skeleton(width: 220, height: 34),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.gap16),
        const Skeleton(width: double.infinity, height: 48),
        const SizedBox(height: AppSpacing.gap16),
        const Skeleton(width: double.infinity, height: 72),
      ],
    );
  }
}
