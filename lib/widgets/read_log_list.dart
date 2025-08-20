import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/achievement_definition.dart';
import 'badge_icon.dart';
import 'comment_drawer.dart';
import 'comment_section.dart';
import 'common_styles.dart';

/// Displays a list of read log entries.
class ReadLogList extends StatelessWidget {
  /// Log entries to show.
  final List<Map<String, dynamic>> logs;

  /// Callback when the like button is pressed.
  final void Function(String uid) onToggleLike;

  /// Callback when a comment is added.
  final Future<Comment> Function(String uid, String message) onAddComment;

  /// Name of the current user for comment drawers.
  final String commenterName;

  const ReadLogList({
    super.key,
    required this.logs,
    required this.onToggleLike,
    required this.onAddComment,
    required this.commenterName,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isLiked = (log['liked'] as bool? ?? false);
        final isFirst = (log['firstReader'] as bool? ?? false);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                  ),
                  title: Text(
                    '${log['name']} read today!',
                    style: AppTextStyles.subtitle,
                  ),
                  subtitle: () {
                    final likeNames = (log['likeNames'] as List?) ?? [];
                    if (likeNames.isEmpty) return null;

                    const maxToShow = 3;
                    final displayText = likeNames.length > maxToShow
                        ? '${likeNames.take(maxToShow).join(", ")} +${likeNames.length - maxToShow} more'
                        : likeNames.join(", ");

                    return Text('Liked by $displayText');
                  }(),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFirst)
                        Tooltip(
                          message: 'First reader of the day',
                          child: BadgeIcon(
                            imageUrl: allAchievements
                                .firstWhere((a) => a.id == 'firstReader')
                                .imageUrl,
                            iconData: allAchievements
                                .firstWhere((a) => a.id == 'firstReader')
                                .icon,
                            size: 24,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: IconButton(
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              key: ValueKey<bool>(isLiked),
                              color: isLiked ? Colors.red : null,
                            ),
                          ),
                          onPressed: isLiked
                              ? null
                              : () => onToggleLike(log['uid'] as String),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.mode_comment_outlined),
                        onPressed: () {
                          CommentDrawer.show(
                            context,
                            comments: List<Comment>.from(
                                log['comments'] as List<Comment>),
                            onAdd: (msg) =>
                                onAddComment(log['uid'] as String, msg),
                            commenterName: commenterName,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                CommentSection(
                  comments:
                      List<Comment>.from(log['comments'] as List<Comment>),
                  onAdd: (msg) => onAddComment(log['uid'] as String, msg),
                  showInput: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
