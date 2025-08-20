import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/group_members_section.dart';

void main() {
  testWidgets('displays member names', (tester) async {
    final membersStream = Stream.value(['Alice', 'Bob']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupMembersSection(membersStream: membersStream),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
