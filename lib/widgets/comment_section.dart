import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';

import '../models/comment.dart';

/// Displays a list of comments and a field to add a new one.
class CommentSection extends StatefulWidget {
  /// Existing comments to display.
  final List<Comment> comments;

  /// Callback when a new comment should be added.
  final Future<void> Function(String message) onAdd;

  /// Whether to show the input field for adding comments.
  final bool showInput;

  /// Optional scroll controller for the comments list.
  final ScrollController? scrollController;

  /// Creates a [CommentSection].
  const CommentSection({
    super.key,
    required this.comments,
    required this.onAdd,
    this.showInput = true,
    this.scrollController,
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
    setState(() => _sending = true);
    try {
      await widget.onAdd(text);
      if (mounted) {
        _controller.clear();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to add comment: $e');
      }
      await ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add comment. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ListView.builder(
            controller: widget.scrollController,
            shrinkWrap: true,
            itemCount: widget.comments.length,
            itemBuilder: (context, index) {
              final c = widget.comments[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${c.authorName}: ${c.message}'),
              );
            },
          ),
        ),
        if (widget.showInput)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration:
                      const InputDecoration(hintText: 'Add a comment...'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _sending
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
  }
}
