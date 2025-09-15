import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/widgets/group_members_section.dart';

void main() {
  testWidgets('displays member progress', (tester) async {
    final membersStream = Stream.value([
      const GroupMemberProgressData(uid: '1', name: 'Alice', completion: 1),
      const GroupMemberProgressData(
        uid: '2',
        name: 'Bob',
        completion: 0.5,
      ),
    ]);
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
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    final indicators = tester
        .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))
        .toList();
    expect(indicators, hasLength(2));
    expect(indicators[0].value, 1);
    expect(indicators[1].value, 0.5);
  });
}
