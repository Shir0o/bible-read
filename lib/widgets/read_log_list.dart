import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/achievement_definition.dart';
import '../models/read_log.dart';
import 'badge_icon.dart';
import 'comment_drawer.dart';
import 'comment_section.dart';
import 'common_styles.dart';

/// Displays a list of read log entries.
class ReadLogList extends StatelessWidget {
  /// Log entries to show.
  final List<ReadLog> logs;

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
        final isLiked = log.liked;
        final isFirst = log.firstReader;
        return CommonStyles.buildTappableCard(
          context: context,
          onTap: () {},
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), // Added horizontal margin for "breathing room"
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), // Adjusted padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                   const Icon(Icons.check_circle, color: Colors.green, size: 20),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         // Name is primary
                         Text(
                           log.name,
                           style: AppTextStyles.subtitle.copyWith(
                             fontWeight: FontWeight.w600,
                             height: 1.2,
                           ),
                         ),
                         const SizedBox(height: 2),
                         // Action context is secondary
                         Text(
                           'read today',
                           style: AppTextStyles.body.copyWith(
                             color: Theme.of(context).colorScheme.onSurfaceVariant,
                             fontSize: 13,
                           ),
                         ),
                       ],
                     ),
                   ),
                    /* Gamification removed: First Reader badge
                    if (isFirst)
                      Tooltip(...)
                    */
                  ],
                ),

                const SizedBox(height: 12), // Spacing between header and interactions

                // Encouragement Text
                if (log.likeNames.isNotEmpty) ...[
                   Text(
                    () {
                      final likeNames = log.likeNames;
                      const maxToShow = 3;
                      final displayText = likeNames.length > maxToShow
                          ? '${likeNames.take(maxToShow).join(", ")} +${likeNames.length - maxToShow} more'
                          : likeNames.join(', ');
                      return 'Encouraged by $displayText';
                    }(),
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Action Row: Subtle alignment
                Row(
                   mainAxisAlignment: MainAxisAlignment.start,
                   children: [
                     // Encouragement Button (Heart)
                     Material(
                       color: Colors.transparent,
                       child: InkWell(
                         borderRadius: BorderRadius.circular(20),
                         onTap: isLiked ? null : () => onToggleLike(log.uid),
                         child: Padding(
                           padding: const EdgeInsets.all(8.0), // Larger touch target, visual space
                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               AnimatedSwitcher(
                                 duration: const Duration(milliseconds: 300),
                                 child: Icon(
                                   isLiked ? Icons.favorite : Icons.favorite_border,
                                   key: ValueKey<bool>(isLiked),
                                   color: isLiked 
                                     ? Theme.of(context).colorScheme.primary.withOpacity(0.7) // Muted heart color
                                     : Theme.of(context).colorScheme.outline, // Subtle outline
                                   size: 20,
                                 ),
                               ),
                               if (!isLiked) ...[
                                 const SizedBox(width: 6),
                                 Text(
                                   'Encourage',
                                   style: TextStyle(
                                     fontSize: 13,
                                     color: Theme.of(context).colorScheme.outline,
                                   ),
                                 ),
                               ],
                             ],
                           ),
                         ),
                       ),
                     ),
                     const SizedBox(width: 16),
                     // Comment Button
                     Material(
                       color: Colors.transparent,
                       child: InkWell(
                         borderRadius: BorderRadius.circular(20),
                         onTap: () {
                           CommentDrawer.show(
                             context,
                             comments: log.comments,
                             onAdd: (msg) => onAddComment(log.uid, msg),
                             commenterName: commenterName,
                           );
                         },
                         child: Padding(
                           padding: const EdgeInsets.all(8.0),
                           child: Row(
                             children: [
                               Icon(
                                 Icons.chat_bubble_outline_rounded, // Rounded variant
                                 size: 19,
                                 color: Theme.of(context).colorScheme.outline,
                               ),
                               const SizedBox(width: 6),
                               Text(
                                   log.comments.isEmpty ? 'Comment' : '${log.comments.length}',
                                   style: TextStyle(
                                     fontSize: 13,
                                     color: Theme.of(context).colorScheme.outline,
                                   ),
                               ),
                             ],
                           ),
                         ),
                       ),
                     ),
                   ],
                ),
                
                if (log.comments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: CommentSection(
                      comments: log.comments,
                      onAdd: (msg) => onAddComment(log.uid, msg),
                      showInput: false,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
