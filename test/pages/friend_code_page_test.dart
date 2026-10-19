import 'package:bible_read/pages/friend_code_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/widgets/friend_code_keys.dart';
import 'package:bible_read/widgets/friend_qr_code.dart';
import 'package:bible_read/widgets/join_code_keys.dart';
import 'package:bible_read/widgets/qr_scan_view.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late StubVibrationService vibration;
  late GroupService groupService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'me', displayName: 'Me'),
      signedIn: true,
    );
    vibration = StubVibrationService();
    groupService = GroupService(firestore: firestore);
  });

  Future<void> pumpPage(
    WidgetTester tester,
    FriendService friendService, {
    QrScanViewBuilder? scanViewBuilder,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FriendCodePage(
          auth: auth,
          friendService: friendService,
          groupService: groupService,
          vibrationService: vibration,
          scanViewBuilder: scanViewBuilder,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the QR, the code in two groups of four, and both actions',
      (tester) async {
    final service = FriendService(
      firestore: firestore,
      generateCode: () => '7QK4M2PX',
    );

    await pumpPage(tester, service);

    expect(
      tester.widget<FriendQrCode>(find.byKey(FriendCodeKeys.qrCode)).data,
      '7QK4M2PX',
    );
    expect(find.byKey(FriendCodeKeys.codeText), findsOneWidget);
    expect(find.text('7QK4 M2PX'), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.copyButton), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.shareButton), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
  });

  testWidgets('Reset retires the code and refreshes the QR and text',
      (tester) async {
    final codes = ['7QK4M2PX', 'ABCD2345'];
    final service = FriendService(
      firestore: firestore,
      generateCode: () => codes.removeAt(0),
    );
    await pumpPage(tester, service);

    expect(
      tester.widget<FriendQrCode>(find.byKey(FriendCodeKeys.qrCode)).data,
      '7QK4M2PX',
    );

    await tester.tap(find.byKey(FriendCodeKeys.resetButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<FriendQrCode>(find.byKey(FriendCodeKeys.qrCode)).data,
      'ABCD2345',
    );
    expect(find.text('ABCD 2345'), findsOneWidget);
    expect(find.text('7QK4 M2PX'), findsNothing);
    expect(
      (await firestore.collection('friendCodes').doc('7QK4M2PX').get()).exists,
      isFalse,
    );
    expect(
      (await firestore.collection('friendCodes').doc('ABCD2345').get()).exists,
      isTrue,
    );
  });

  testWidgets('"Scan or enter their code" opens the add side', (tester) async {
    final service = FriendService(firestore: firestore);
    await pumpPage(
      tester,
      service,
      scanViewBuilder: (context, onDetect) =>
          const ColoredBox(color: Colors.black),
    );

    await tester.tap(find.byKey(FriendCodeKeys.enterCodeButton));
    await tester.pumpAndSettle();

    expect(find.byKey(JoinCodeKeys.codeField), findsOneWidget);
  });
}
