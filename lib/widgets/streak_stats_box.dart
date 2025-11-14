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

  /// Summary of paired streak links, if available.
  final FriendlyStreakLinksSummary? friendSummary;

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
    this.friendSummary,
    this.selectedPartnerId,
    this.onPartnerSelected,
    this.onInviteFriend,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final summary = friendSummary ?? FriendlyStreakLinksSummary.empty;
    final showFriendSummary = friendSummary != null;
    final selectedLink = _selectedPartner(summary);
    final bestLink =
        summary.activeLinks.isNotEmpty ? summary.activeLinks.first : null;
    final dropdownNeeded =
        summary.activeLinks.length > 1 && onPartnerSelected != null;
    final reachedLimit =
        summary.activeLinks.length >= FriendService.maxActiveStreakLinks;

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
          if (showFriendSummary && summary.activeLinks.isNotEmpty)
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
                    items: summary.activeLinks
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
          else if (showFriendSummary && summary.pendingLinks.isNotEmpty)
            Text(
              summary.pendingLinks.length == 1
                  ? 'Pending invite: ${_displayName(summary.pendingLinks.first)}'
                  : 'Pending invites: ${summary.pendingLinks.length}',
              style: AppTextStyles.body,
            )
          else if (showFriendSummary)
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
          if (showFriendSummary && reachedLimit)
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

  FriendStreakLink? _selectedPartner(FriendlyStreakLinksSummary summary) {
    if (selectedPartnerId == null) {
      return summary.activeLinks.isNotEmpty ? summary.activeLinks.first : null;
    }
    for (final link in summary.activeLinks) {
      if (link.partnerUid == selectedPartnerId) {
        return link;
      }
    }
    return summary.activeLinks.isNotEmpty ? summary.activeLinks.first : null;
  }

  String _displayName(FriendStreakLink link) {
    return link.partnerName?.trim().isEmpty ?? true
        ? 'Friend'
        : link.partnerName!;
  }
}
