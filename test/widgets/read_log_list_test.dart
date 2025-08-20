import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_log_list.dart';
import 'package:bible_read/models/comment.dart';

void main() {
  testWidgets('like button triggers callback', (tester) async {
    String? liked;
    final logs = [
      {
        'uid': '1',
        'name': 'Alice',
        'liked': false,
        'likeNames': <String>[],
        'firstReader': false,
        'comments': <Comment>[],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogList(
            logs: logs,
            onToggleLike: (uid) => liked = uid,
            onAddComment: (uid, msg) async => Comment(
              id: 'c1',
              uid: uid,
              authorName: 'Tester',
              message: msg,
              timestamp: DateTime.now(),
            ),
            commenterName: 'Tester',
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(liked, '1');
  });
}
