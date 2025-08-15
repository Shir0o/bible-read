import 'package:flutter/material.dart';

import '../models/comment.dart';
import 'comment_section.dart';

/// Displays comments in a modal bottom sheet.
class CommentDrawer extends StatefulWidget {
  /// Comments to display initially.
  final List<Comment> comments;

  /// Callback when a new comment is posted.
  /// Should return the persisted [Comment] with its Firestore id.
  final Future<Comment> Function(String message) onAdd;

  /// Name of the current user posting comments.
  final String commenterName;

  /// Scroll controller for wrapping [CommentSection] when displayed in a
  /// [DraggableScrollableSheet].
  final ScrollController? controller;

  /// Creates a [CommentDrawer].
  const CommentDrawer({
    super.key,
    required this.comments,
    required this.onAdd,
    required this.commenterName,
    this.controller,
  });

  @override
  State<CommentDrawer> createState() => _CommentDrawerState();

  /// Opens the drawer as a bottom sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required List<Comment> comments,
    required Future<Comment> Function(String message) onAdd,
    required String commenterName,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.33,
          minChildSize: 0.33,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return CommentDrawer(
              comments: comments,
              onAdd: onAdd,
              commenterName: commenterName,
              controller: scrollController,
            );
          },
        ),
      ),
    );
  }
}

class _CommentDrawerState extends State<CommentDrawer> {
  late List<Comment> _comments;

  @override
  void initState() {
    super.initState();
    _comments = List<Comment>.from(widget.comments);
  }

  Future<Comment> _handleAdd(String message) async {
    final temp = Comment(
      id: '',
      uid: '',
      authorName: widget.commenterName,
      message: message,
      timestamp: DateTime.now(),
    );
    setState(() => _comments.add(temp));
    try {
      final saved = await widget.onAdd(message);
      if (!mounted) return saved;
      setState(() {
        final index = _comments.indexOf(temp);
        if (index != -1) {
          _comments[index] = saved;
        }
      });
      return saved;
    } catch (e) {
      if (mounted) {
        setState(() => _comments.remove(temp));
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: CommentSection(
        comments: _comments,
        onAdd: _handleAdd,
        scrollController: widget.controller,
        showSendProgress: false,
      ),
    );

    return SafeArea(
      child: content,
    );
  }
}
