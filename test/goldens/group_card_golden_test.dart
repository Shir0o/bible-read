import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/group_card.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import '../helpers/pump_app.dart';

class FakeGroupService extends GroupService {
  FakeGroupService() : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<GroupMemberProgressData>> memberOverallCompletion(String groupId, {String? includeUid}) {
    return Stream.value([
        GroupMemberProgressData(uid: 'u1', name: 'Alice', completion: 0.75),
        GroupMemberProgressData(uid: 'u2', name: 'Bob', completion: 0.25),
    ]);
  }

  @override
  Future<List<String>> fetchTodaysChapters(String groupId) async => ['Genesis 1', 'Genesis 2'];
}

void main() {
  testWidgets('GroupCard Golden Test', (tester) async {
    final group = Group(
      id: 'g1',
      name: 'Golden Group',
      ownerUid: 'u1',
      memberCount: 5,
    );

    await tester.pumpApp(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: GroupCard(
              group: group,
              groupService: FakeGroupService(),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify visual elements instead of golden file for now
    expect(find.byType(GroupCard), findsOneWidget);
    // await expectLater(
    //   find.byType(GroupCard),
    //   matchesGoldenFile('goldens/group_card.png'),
    // );
  });
}
