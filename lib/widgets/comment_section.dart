import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/error_logger.dart';
import 'common_styles.dart';

import '../models/comment.dart';

/// Displays a list of comments and a field to add a new one.
class CommentSection extends StatefulWidget {
  /// Existing comments to display.
  final List<Comment> comments;

  /// Callback when a new comment should be added.
  final Future<Comment> Function(String message) onAdd;

  /// Whether to show the input field for adding comments.
  final bool showInput;

  /// Optional scroll controller for the comments list.
  final ScrollController? scrollController;

  /// Whether to display a progress indicator in the send button while
  /// a comment is being posted.
  final bool showSendProgress;

  /// Creates a [CommentSection].
  const CommentSection({
    super.key,
    required this.comments,
    required this.onAdd,
    this.showInput = true,
    this.scrollController,
    this.showSendProgress = true,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() => _sending = true);

    void handleError(Object e, StackTrace st) {
      if (kDebugMode) {
        debugPrint('Failed to add comment: $e');
      }
      unawaited(ErrorLogger.log(e, st));
      if (mounted) {
        _controller
          ..text = text
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add comment. Please try again.'),
          ),
        );
      }
    }

    Future<Comment> future;
    try {
      future = widget.onAdd(text);
      setState(() {});
      await future;
    } catch (e, st) {
      handleError(e, st);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final listView = ListView.builder(
          controller: widget.scrollController,
          shrinkWrap: !hasBoundedHeight,
          physics: hasBoundedHeight
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          itemCount: widget.comments.length,
          itemBuilder: (context, index) {
            final c = widget.comments[index];
            return CommonStyles.buildTappableCard(
              context: context,
              onTap: () {},
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.authorName),
                subtitle: Text(c.message),
              ),
            );
          },
        );

        final listChild = hasBoundedHeight
            ? Flexible(fit: FlexFit.loose, child: listView)
            : listView;

        return Column(
          mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            listChild,
            if (widget.showInput)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.text,
                      decoration:
                          const InputDecoration(hintText: 'Write a word of encouragement...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sending
                        ? null
                        : () {
                            _submit();
                          },
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _sending && widget.showSendProgress
                          ? const SizedBox(
                              key: ValueKey('progress'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.send,
                              key: ValueKey('send'),
                            ),
                    ),
                    label: const Text('Post'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
