import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/error_logger.dart';
import '../services/friend_invite.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/join_code_service.dart';
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

/// Which half of "Add a friend" is showing.
enum _FriendTab { myCode, scan }

/// "Add a friend": the reader's personal friend code as a QR (and text) they
/// can copy, share or reset, and a Scan view that reads someone else's code
/// and routes it through the same "Have a code?" flow (ADR-0012 V2).
class FriendCodePage extends StatefulWidget {
  /// Auth used to identify the code's owner.
  final FirebaseAuth auth;

  /// Friend code operations.
  final FriendService friendService;

  /// Group service, for the "Enter a code" route.
  final GroupService groupService;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Camera scanner for the Scan tab. Defaults to the real camera; tests
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
  _FriendTab _tab = _FriendTab.myCode;

  /// Inline message under the Scan view when a payload is not a code.
  String? _scanError;

  /// True while the scanner should ignore detections: from the moment a
  /// payload is routed until its QR has been out of frame for a moment, so
  /// returning from the confirm screen does not immediately re-open it.
  bool _scanPaused = false;

  /// Resumes scanning once detections stop arriving (the code left the frame).
  Timer? _scanIdle;

  @override
  void dispose() {
    _scanIdle?.cancel();
    super.dispose();
  }

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
          'The current code will stop working. Anyone you are already friends '
          'with stays your friend.',
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

  void _openEnterCode() {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinByCodePage(
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          friendService: widget.friendService,
        ),
      ),
    );
  }

  /// Routes a scanned payload like "Have a code?": six characters to the group
  /// flow, eight to the friend flow, anything else is not a Bible Read code.
  Future<void> _onScanned(String raw) async {
    if (!mounted) return;
    if (_scanPaused) {
      // A code is still in frame — keep the scanner paused until it leaves.
      _armScanResume();
      return;
    }

    final code = FriendService.normalize(raw);
    final isGroup = code.length == JoinCodeService.codeLength;
    final isFriend = code.length == FriendService.codeLength;
    if (!isGroup && !isFriend) {
      unawaited(widget.vibrationService.lightImpact());
      setState(() => _scanError = 'Not a Bible Read code.');
      return;
    }

    _scanPaused = true;
    unawaited(widget.vibrationService.lightImpact());
    setState(() => _scanError = null);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinByCodePage(
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          friendService: widget.friendService,
          initialCode: code,
        ),
      ),
    );
    if (!mounted) return;
    _armScanResume();
  }

  /// Re-arms the resume timer. Called again on every detection while paused, so
  /// the scanner only resumes after the code has been out of frame for a beat.
  void _armScanResume() {
    _scanIdle?.cancel();
    _scanIdle = Timer(const Duration(seconds: 2), () {
      _scanPaused = false;
    });
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.hPadding,
                AppSpacing.gap4,
                AppSpacing.hPadding,
                AppSpacing.gap12,
              ),
              child: SegmentedButton<_FriendTab>(
                segments: const [
                  ButtonSegment(
                    value: _FriendTab.myCode,
                    label: Text('My code'),
                  ),
                  ButtonSegment(
                    value: _FriendTab.scan,
                    label: Text('Scan'),
                  ),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  final next = selection.first;
                  if (next == _tab) return;
                  unawaited(widget.vibrationService.lightImpact());
                  setState(() {
                    _tab = next;
                    _scanError = null;
                  });
                },
              ),
            ),
            Expanded(
              child: _tab == _FriendTab.myCode
                  ? _buildMyCodeTab()
                  : _buildScanTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCodeTab() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: CommonStyles.backgroundDecoration(colorScheme),
      child: SafeArea(
        child: SkeletonLoader(
          loading: _loading,
          skeleton: const _FriendCodeSkeleton(),
          child: _loading ? const SizedBox.shrink() : _buildLoadedBody(context),
        ),
      ),
    );
  }

  Widget _buildScanTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final buildScan = widget.scanViewBuilder ?? cameraQrScanView;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black, child: buildScan(context, _onScanned)),
        const IgnorePointer(child: _ScanOverlay()),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_scanError != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.gap16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.gap16,
                        vertical: AppSpacing.gap12,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppSpacing.rCard),
                      ),
                      child: Text(
                        _scanError!,
                        key: FriendCodeKeys.scanError,
                        style: AppTextStyles.body(context),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.gap8),
                  child: TextButton(
                    key: FriendCodeKeys.enterCodeButton,
                    onPressed: _openEnterCode,
                    style: TextButton.styleFrom(
                      // token-exempt: white action over the dark camera preview
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Enter a code instead'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

    final rawName = widget.auth.currentUser?.displayName?.trim();
    final displayName = (rawName == null || rawName.isEmpty) ? 'You' : rawName;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      children: [
        Text(
          'Give this code to someone you want to read alongside. When they '
          'enter it, you’re friends.',
          style: AppTextStyles.body(context).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.gap16),
        CommonStyles.buildCard(
          context: context,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.gap24,
              horizontal: AppSpacing.gap16,
            ),
            child: Column(
              children: [
                FriendQrCode(data: code, key: FriendCodeKeys.qrCode),
                const SizedBox(height: AppSpacing.gap16),
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.gap2),
                Text(
                  'Scan to be friends',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.gap20),
                Text(
                  'YOUR FRIEND CODE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.6,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.gap12),
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
                label: const Text('Copy'),
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
        const SizedBox(height: AppSpacing.gap8),
        Text(
          'Anyone with this code can add you. ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
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
                : const Text('Reset code to stop the old one working'),
          ),
        ),
        const SizedBox(height: AppSpacing.gap24),
        CommonStyles.buildCard(
          context: context,
          child: InkWell(
            onTap: _openEnterCode,
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gap16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Got a code from someone? Enter it',
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
        const Skeleton(width: double.infinity, height: 40),
        const SizedBox(height: AppSpacing.gap16),
        CommonStyles.buildCard(
          context: context,
          child: const Padding(
            padding: EdgeInsets.symmetric(
              vertical: AppSpacing.gap24,
              horizontal: AppSpacing.gap16,
            ),
            child: Column(
              children: [
                Skeleton(width: 200, height: 200),
                SizedBox(height: AppSpacing.gap16),
                Skeleton(width: 120, height: 20),
                SizedBox(height: AppSpacing.gap12),
                Skeleton(width: 140, height: 12),
                SizedBox(height: AppSpacing.gap12),
                Skeleton(width: 220, height: 34),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.gap16),
        const Skeleton(width: double.infinity, height: 48),
      ],
    );
  }
}

/// The scanning frame: a rounded guide and the "point at" hint, drawn over the
/// camera preview.
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(AppSpacing.rCard),
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),
          const Text(
            'Point at your friend’s code',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
