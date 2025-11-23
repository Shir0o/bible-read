import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_streak_link.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/friendly_streak_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/navigation_menu_scope.dart';
import 'friends_page.dart';
import 'invite_streak_page.dart';

/// Dedicated page for managing friendly streak partners.
class FriendlyStreakPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendlyStreakService friendlyStreakService;

  FriendlyStreakPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FriendlyStreakService? friendlyStreakService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        friendlyStreakService = friendlyStreakService ??
            FriendlyStreakService(firestore: firestore);

  @override
  State<FriendlyStreakPage> createState() => _FriendlyStreakPageState();
}

class _FriendlyStreakPageState extends State<FriendlyStreakPage> {
  FriendlyStreakLinksSummary _summary = FriendlyStreakLinksSummary.empty;
  int _currentStreak = 0;
  int _longestStreak = 0;
  int _totalReadDays = 0;
  int? _remainingGraceCredits;
  bool _isLoading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadFriendlyStreak();
  }

  Future<void> _loadFriendlyStreak() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isLoading = false;
        _summary = FriendlyStreakLinksSummary.empty;
        _loadError = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = false;
    });

    try {
      final summaryFuture = widget.firestore
          .collection('users')
          .doc(uid)
          .collection('summary')
          .doc('data')
          .get();
      final friendSummaryFuture = widget.friendlyStreakService.fetchLinks(uid);
      final summaryDoc = await summaryFuture;
      final friendSummary = await friendSummaryFuture;
      final data = summaryDoc.data() ?? {};
      final now = DateTime.now();
      final currentMonthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      int? remainingGraceCredits;
      if (data['graceCreditsMonth'] == currentMonthKey &&
          data['graceCreditsAvailable'] is int) {
        remainingGraceCredits = data['graceCreditsAvailable'] as int;
      }

      if (!mounted) return;
      setState(() {
        _currentStreak = data['streak'] ?? 0;
        _longestStreak = data['longestStreak'] ?? _currentStreak;
        _totalReadDays = data['totalReadDays'] ?? 0;
        _remainingGraceCredits = remainingGraceCredits;
        _summary = friendSummary;
        _isLoading = false;
        _loadError = false;
      });
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = true;
      });
    }
  }

  void _openFriendsPage() {
    final scope = NavigationMenuScope.maybeOf(context);
    if (scope != null) {
      scope.onNavigate(scope.friendsIndex);
      return;
    }
    Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder: (_) => FriendsPage(auth: widget.auth),
      ),
    );
  }

  Widget _buildPartnerListCard() {
    final summary = _summary;
    if (!summary.hasPartners) {
      return CommonStyles.buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No streak partners yet. Invite a friend to share progress.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InviteStreakPage(
                      auth: widget.auth,
                      friendService: FriendService(firestore: widget.firestore),
                    ),
                  ),
                );
              },
              child: const Text('Invite a friend'),
            ),
          ],
        ),
      );
    }

    return CommonStyles.buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.activeLinks.isNotEmpty) ...[
            const Text('Active partners', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            ...summary.activeLinks.map(_buildActivePartnerTile),
          ],
          if (summary.pendingLinks.isNotEmpty) ...[
            if (summary.activeLinks.isNotEmpty) const SizedBox(height: 16),
            const Text('Pending invites', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            ...summary.pendingLinks.map(_buildPendingPartnerTile),
          ],
        ],
      ),
    );
  }

  Widget _buildActivePartnerTile(FriendStreakLink link) {
    return ListTile(
      key: ValueKey('partner-${link.partnerUid}'),
      contentPadding: EdgeInsets.zero,
      title: Text(
        _displayName(link),
        style: AppTextStyles.body,
      ),
      subtitle: Text(
        '${link.currentStreak} day${link.currentStreak == 1 ? '' : 's'}',
        style: AppTextStyles.body,
      ),
    );
  }

  Widget _buildPendingPartnerTile(FriendStreakLink link) {
    final detail =
        link.isIncoming ? 'Respond to invite' : 'Waiting for partner';
    return ListTile(
      key: ValueKey('pending-${link.partnerUid}'),
      contentPadding: EdgeInsets.zero,
      title: Text(_displayName(link), style: AppTextStyles.body),
      subtitle: Text(detail, style: AppTextStyles.body),
    );
  }

  Widget _buildErrorNotice() {
    return CommonStyles.buildCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "We couldn't refresh friendly streaks. Pull down to try again.",
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }

  String _displayName(FriendStreakLink link) {
    return link.partnerName?.trim().isEmpty ?? true
        ? 'Friend'
        : link.partnerName!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Friendly streaks',
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'friendly-streak-fab',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InviteStreakPage(
                auth: widget.auth,
                friendService: FriendService(firestore: widget.firestore),
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: RefreshIndicator(
          onRefresh: _loadFriendlyStreak,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              if (_loadError) ...[
                _buildErrorNotice(),
                const SizedBox(height: 16),
              ],
              _buildPartnerListCard(),
            ],
          ),
        ),
      ),
    );
  }
}
