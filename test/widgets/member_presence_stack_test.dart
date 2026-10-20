import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/widgets/member_presence_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the last avatar keeps its full width so nothing overlaps it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MemberPresenceStack(
            members: const [
              GroupMemberProgressData(uid: 'a', name: 'Ann', completion: 1),
              GroupMemberProgressData(uid: 'b', name: 'Ben', completion: 1),
              GroupMemberProgressData(uid: 'c', name: 'Cal', completion: 1),
            ],
            size: 36,
            max: 5,
            showDoneBadge: false,
          ),
        ),
      ),
    );

    // Two overlapped avatars (0.7 × 36) plus one full avatar.
    expect(tester.getSize(find.byType(MemberPresenceStack)).width,
        closeTo(36 * 0.7 * 2 + 36, 0.01));
  });
}
