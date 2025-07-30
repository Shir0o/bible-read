import 'package:flutter/material.dart';

import '../models/comment.dart';
import 'comment_section.dart';

/// Displays comments in a modal bottom sheet.
class CommentDrawer extends StatelessWidget {
  /// Comments to display.
  final List<Comment> comments;

  /// Callback when a new comment is posted.
  final Future<void> Function(String message) onAdd;

  /// Scroll controller for wrapping [CommentSection] when displayed in a
  /// [DraggableScrollableSheet].
  final ScrollController? controller;

  /// Creates a [CommentDrawer].
  const CommentDrawer({
    super.key,
    required this.comments,
    required this.onAdd,
    this.controller,
  });

  /// Opens the drawer as a bottom sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required List<Comment> comments,
    required Future<void> Function(String message) onAdd,
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
              controller: scrollController,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: CommentSection(
        comments: comments,
        onAdd: onAdd,
      ),
    );

    return SafeArea(
      child: controller == null
          ? content
          : SingleChildScrollView(
              controller: controller,
              child: content,
            ),
    );
  }
}
