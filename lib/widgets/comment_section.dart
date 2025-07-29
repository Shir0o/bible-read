import 'package:flutter/material.dart';

import '../models/comment.dart';

/// Displays a list of comments and a field to add a new one.
class CommentSection extends StatefulWidget {
  /// Existing comments to display.
  final List<Comment> comments;

  /// Callback when a new comment should be added.
  final Future<void> Function(String message) onAdd;

  /// Whether to show the input field for adding comments.
  final bool showInput;

  /// Creates a [CommentSection].
  const CommentSection({
    super.key,
    required this.comments,
    required this.onAdd,
    this.showInput = true,
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
    } catch (e) {
      debugPrint('Failed to add comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in widget.comments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${c.authorName}: ${c.message}'),
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
              ElevatedButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post'),
              ),
            ],
          ),
      ],
    );
  }
}
