import 'dart:async';
import 'package:flutter/material.dart';
import '../models/read_log.dart';
import '../models/comment.dart';
import '../widgets/common_styles.dart';
import '../services/vibration_service.dart';

class FeedCard extends StatefulWidget {
  final ReadLog log;
  final VoidCallback onToggleLike;
  final Future<Comment> Function(String message) onAddComment;
  final String currentUserName;

  const FeedCard({
    super.key,
    required this.log,
    required this.onToggleLike,
    required this.onAddComment,
    required this.currentUserName,
    this.vibrationService,
  });

  final VibrationService? vibrationService;

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _commentController.removeListener(_onTextChanged);
    _commentController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await widget.onAddComment(text);
      if (mounted) {
        _commentController.clear();
        // Keep expanded to show new comment
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLiked = widget.log.liked;

    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 8,
      shadowColor: colorScheme.shadow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Tappable Area
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(24),
              bottom: _isExpanded ? Radius.zero : const Radius.circular(24),
            ),
            // Light, airy layout with generous padding
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Name & Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar placeholder or actual avatar could go here if available
                      // For now, just the text content as requested
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // User name: Bold and prominent
                            Text(
                              widget.log.name,
                              style: AppTextStyles.title.copyWith(
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Reading status row
                            MergeSemantics(
                              child: Row(
                                children: [
                                  // Leading green check icon
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colorScheme.tertiaryContainer,
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Text: "Read today"
                                  Text(
                                    'Read today',
                                    style: AppTextStyles.body.copyWith(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Social feedback row: "Encouraged by..."
                  if (widget.log.likeNames.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // Small heart-in-circle icon
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.favorite,
                              size: 12,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _buildLikeText(widget.log.likeNames),
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              // Muted but friendly tone
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Bottom action row
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      // Encourage Action
                      _ActionButton(
                        icon: isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: 'Encourage',
                        // Warm dynamic color if liked
                        color: isLiked
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        backgroundColor:
                            isLiked ? colorScheme.primaryContainer : null,
                        isSelected: isLiked,
                        onTap: () {
                          (widget.vibrationService ?? const VibrationService())
                              .lightImpact();
                          widget.onToggleLike();
                        },
                      ),
                      const SizedBox(width: 12),

                      // Comment Action
                      _ActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        // Count e.g. "1"
                        label: widget.log.comments.isNotEmpty
                            ? '${widget.log.comments.length}'
                            : 'Comment',
                        color: colorScheme.onSurfaceVariant,
                        isSelected: false,
                        onTap: () {
                          if (!_isExpanded) {
                            _toggleExpanded();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content (Comments + Composer)
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                if (widget.log.comments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.log.comments.map((comment) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${comment.authorName}:',
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  comment.message,
                                  style: AppTextStyles.body.copyWith(
                                    fontSize: 13,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                // Inline Composer
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5)),
                          ),
                          child: TextField(
                            controller: _commentController,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            decoration: InputDecoration(
                              hintText: 'Write a word of encouragement...',
                              hintStyle: TextStyle(
                                  fontSize: 13, color: colorScheme.outline),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              suffixIcon: _commentController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      tooltip: 'Clear comment',
                                      onPressed: _commentController.clear,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    )
                                  : null,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onSubmitted: (_) => _submitComment(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send Button
                      IconButton.filled(
                        tooltip: 'Send comment',
                        onPressed: _isSending ? null : _submitComment,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          minimumSize: const Size(40, 40),
                        ),
                        icon: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  String _buildLikeText(List<String> likeNames) {
    const maxToShow = 2;
    if (likeNames.length <= maxToShow) {
      return likeNames.join(' & ');
    } else {
      return '${likeNames.take(maxToShow).join(', ')} and ${likeNames.length - maxToShow} others';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final bool? isSelected;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
