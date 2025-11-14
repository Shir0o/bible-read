import 'package:flutter/material.dart';

import '../models/friend_streak_link.dart';
import '../services/friend_service.dart';
import '../services/friendly_streak_service.dart';
import 'common_styles.dart';

/// Displays streak statistics in a card.
class StreakStatsBox extends StatelessWidget {
  /// Current streak length in days.
  final int currentStreak;

  /// Longest streak length in days.
  final int longestStreak;

  /// Total number of days the user has read.
  final int totalReadDays;

  /// Count of read days within the selected period.
  final int periodCount;

  /// Label for the selected period, e.g. "This week".
  final String periodLabel;

  /// Remaining grace credits available for the current month, if known.
  final int? remainingGraceCredits;

  /// Summary of paired streak links.
  final FriendlyStreakLinksSummary friendSummary;

  /// Partner currently selected by the user.
  final String? selectedPartnerId;

  /// Called when the selected partner changes.
  final ValueChanged<String?>? onPartnerSelected;

  /// Optional callback prompting users to invite a friend.
  final VoidCallback? onInviteFriend;

  /// Optional description explaining how streak tracking works.
  final Widget? description;

  const StreakStatsBox({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalReadDays,
    required this.periodCount,
    required this.periodLabel,
    this.remainingGraceCredits,
    this.friendSummary = FriendlyStreakLinksSummary.empty,
    this.selectedPartnerId,
    this.onPartnerSelected,
    this.onInviteFriend,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLink = _selectedPartner();
    final bestLink = friendSummary.activeLinks.isNotEmpty
        ? friendSummary.activeLinks.first
        : null;
    final dropdownNeeded =
        friendSummary.activeLinks.length > 1 && onPartnerSelected != null;
    final reachedLimit =
        friendSummary.activeLinks.length >= FriendService.maxActiveStreakLinks;

    return CommonStyles.buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current streak: $currentStreak', style: AppTextStyles.body),
          Text('Longest streak: $longestStreak', style: AppTextStyles.body),
          Text('Total read days: $totalReadDays', style: AppTextStyles.body),
          Text('$periodLabel: $periodCount', style: AppTextStyles.body),
          if (remainingGraceCredits != null)
            Text(
              'Grace credits remaining: $remainingGraceCredits',
              style: AppTextStyles.body,
            ),
          if (friendSummary.activeLinks.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedLink != null
                      ? 'Streak with ${_displayName(selectedLink)}: ${selectedLink.currentStreak} day${selectedLink.currentStreak == 1 ? '' : 's'}'
                      : 'Best partner streak: ${bestLink?.currentStreak ?? 0} day${bestLink?.currentStreak == 1 ? '' : 's'} with ${bestLink == null ? 'a friend' : _displayName(bestLink)}',
                  style: AppTextStyles.body,
                ),
                if (dropdownNeeded) ...[
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedLink?.partnerUid ?? bestLink?.partnerUid,
                    onChanged: onPartnerSelected,
                    items: friendSummary.activeLinks
                        .map(
                          (link) => DropdownMenuItem(
                            value: link.partnerUid,
                            child: Text(_displayName(link)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            )
          else if (friendSummary.pendingLinks.isNotEmpty)
            Text(
              friendSummary.pendingLinks.length == 1
                  ? 'Pending invite: ${_displayName(friendSummary.pendingLinks.first)}'
                  : 'Pending invites: ${friendSummary.pendingLinks.length}',
              style: AppTextStyles.body,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No streak partners yet. Invite a friend to share progress.',
                  style: AppTextStyles.body,
                ),
                if (onInviteFriend != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: onInviteFriend,
                      child: const Text('Invite a friend'),
                    ),
                  ),
              ],
            ),
          if (reachedLimit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'You reached the limit of ${FriendService.maxActiveStreakLinks} active partners.',
                style: AppTextStyles.body,
              ),
            ),
          if (description != null) ...[const SizedBox(height: 8), description!],
        ],
      ),
    );
  }

  FriendStreakLink? _selectedPartner() {
    if (selectedPartnerId == null) {
      return friendSummary.activeLinks.isNotEmpty
          ? friendSummary.activeLinks.first
          : null;
    }
    for (final link in friendSummary.activeLinks) {
      if (link.partnerUid == selectedPartnerId) {
        return link;
      }
    }
    return friendSummary.activeLinks.isNotEmpty
        ? friendSummary.activeLinks.first
        : null;
  }

  String _displayName(FriendStreakLink link) {
    return link.partnerName?.trim().isEmpty ?? true
        ? 'Friend'
        : link.partnerName!;
  }
}
