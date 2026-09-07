import 'package:bible_read/models/group.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/share_code_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/widgets/join_code_keys.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late StubVibrationService vibration;
  String? clipboardText;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (message) async {
      if (message.method == 'Clipboard.setData') {
        final args = message.arguments as Map<Object?, Object?>;
        clipboardText = args['text'] as String?;
      } else if (message.method == 'Clipboard.getData') {
        return <String, String?>{'text': clipboardText};
      }
      return null;
    });
    clipboardText = null;
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
    vibration = StubVibrationService();
  });

  Future<Map<String, String>> pumpPage(WidgetTester tester) async {
    final groupId = await groupService.createGroup(
      ownerUid: 'owner',
      name: 'Evening Readers',
    );
    final code = await groupService.joinCodeService.ensureGroupCode(groupId);
    await tester.pumpWidget(
      MaterialApp(
        home: ShareCodePage(
          group: Group(
            id: groupId,
            name: 'Evening Readers',
            ownerUid: 'owner',
            memberCount: 1,
          ),
          groupService: groupService,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return {'groupId': groupId, 'code': code};
  }

  testWidgets('shows the group code for sharing', (tester) async {
    final seeded = await pumpPage(tester);

    final codeText = tester.widget<Text>(
      find.byKey(JoinCodeKeys.codeText),
    );
    expect(codeText.data, seeded['code']);
    expect(find.textContaining('Evening Readers'), findsOneWidget);
  });

  testWidgets('copy puts the code on the clipboard', (tester) async {
    final seeded = await pumpPage(tester);

    await tester.tap(find.byKey(JoinCodeKeys.copyButton));
    await tester.pumpAndSettle();

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, seeded['code']);
  });

  testWidgets('regenerating replaces the code and retires the old one',
      (tester) async {
    final seeded = await pumpPage(tester);

    await tester.tap(find.byKey(JoinCodeKeys.regenerateButton));
    await tester.pumpAndSettle();
    // Confirm the regeneration dialog.
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();

    final codeText = tester.widget<Text>(find.byKey(JoinCodeKeys.codeText));
    expect(codeText.data, isNot(seeded['code']));

    final groupDoc =
        await firestore.collection('groups').doc(seeded['groupId']).get();
    expect(groupDoc.data()?['joinCode'], codeText.data);

    final oldLookup =
        await firestore.collection('joinCodes').doc(seeded['code']).get();
    expect(oldLookup.exists, isFalse);
  });
}
