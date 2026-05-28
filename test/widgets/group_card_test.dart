import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/widgets/group_card.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/services/group_service.dart';
import '../helpers/pump_app.dart';

class FakeGroupService extends GroupService {
  FakeGroupService() : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<GroupMemberProgressData>> memberOverallCompletion(
    String groupId, {
    String? includeUid,
  }) {
    return Stream.value([
      const GroupMemberProgressData(uid: 'u1', name: 'User 1', completion: 0.5),
      const GroupMemberProgressData(uid: 'u2', name: 'User 2', completion: 0.2),
    ]);
  }

  @override
  Future<List<String>> fetchTodaysChapters(String groupId) async {
    return ['Genesis 1', 'Genesis 2'];
  }
}

void main() {
  late GroupService groupService;

  setUp(() {
    groupService = FakeGroupService();
  });

  testWidgets('GroupCard renders correctly with InkWell and Semantics', (
    tester,
  ) async {
    final group = Group(
      id: 'g1',
      name: 'Test Group',
      ownerUid: 'u1',
      memberCount: 2,
    );

    await tester.pumpApp(
      Scaffold(
        body: GroupCard(group: group, groupService: groupService, onTap: () {}),
      ),
    );

    // Settle for FutureBuilder and StreamBuilder
    await tester.pumpAndSettle();

    // Verify content
    expect(find.text('Test Group'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(
      find.textContaining('Reading: Genesis 1, Genesis 2'),
      findsOneWidget,
    );

    // Verify InkWell exists (Visual feedback)
    expect(find.byType(InkWell), findsOneWidget);

    // Verify Semantics
    final semantics = tester.getSemantics(find.byType(InkWell));
    // ignore: deprecated_member_use
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);

    expect(semantics.label, contains('Test Group'));
    expect(semantics.label, contains('35%'));
  });
}
