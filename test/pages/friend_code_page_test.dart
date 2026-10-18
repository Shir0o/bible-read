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

  testWidgets('shows the code in two groups of four', (tester) async {
    final service = FriendService(
      firestore: firestore,
      generateCode: () => '7QK4M2PX',
    );

    await pumpPage(tester, service);

    expect(find.byKey(FriendCodeKeys.codeText), findsOneWidget);
    expect(find.text('7QK4 M2PX'), findsOneWidget);
    expect(find.textContaining('Anyone with this code can add you'),
        findsOneWidget);
  });

  testWidgets('renders a QR for the current code and updates after reset',
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
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<FriendQrCode>(find.byKey(FriendCodeKeys.qrCode)).data,
      'ABCD2345',
    );
  });

  testWidgets('reset produces a new code and retires the old lookup',
      (tester) async {
    final codes = ['7QK4M2PX', 'ABCD2345'];
    final service = FriendService(
      firestore: firestore,
      generateCode: () => codes.removeAt(0),
    );
    await pumpPage(tester, service);
    expect(find.text('7QK4 M2PX'), findsOneWidget);

    await tester.tap(find.byKey(FriendCodeKeys.resetButton));
    await tester.pumpAndSettle();
    expect(find.text('Reset your code?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

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

  group('Scan', () {
    Future<void> openScan(WidgetTester tester) async {
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
    }

    testWidgets('an eight-character payload reaches the friend confirm card',
        (tester) async {
      final codes = ['MNPQRS23', 'ABCDEFGH'];
      final service = FriendService(
        firestore: firestore,
        generateCode: () => codes.removeAt(0),
      );
      await firestore.collection('users').doc('owner').set({'name': 'Mei'});
      final ownerCode = await service.ensureMyCode('owner');

      late ValueChanged<String> emit;
      await pumpPage(
        tester,
        service,
        scanViewBuilder: (context, onDetect) {
          emit = onDetect;
          return const ColoredBox(color: Colors.black);
        },
      );
      await openScan(tester);

      emit(ownerCode);
      await tester.pumpAndSettle();

      expect(find.byKey(FriendCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Mei'), findsOneWidget);
      expect(find.text('Add Mei as a friend'), findsOneWidget);
    });

    testWidgets('a six-character payload routes to the group join flow',
        (tester) async {
      final service = FriendService(firestore: firestore);
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Evening Readers',
      );
      final joinCode = (await firestore.collection('groups').doc(groupId).get())
          .data()!['joinCode'] as String;

      late ValueChanged<String> emit;
      await pumpPage(
        tester,
        service,
        scanViewBuilder: (context, onDetect) {
          emit = onDetect;
          return const ColoredBox(color: Colors.black);
        },
      );
      await openScan(tester);

      emit(joinCode);
      await tester.pumpAndSettle();

      expect(find.byKey(JoinCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Evening Readers'), findsOneWidget);
      expect(find.byKey(FriendCodeKeys.previewCard), findsNothing);
    });

    testWidgets('a payload that is not a code says so', (tester) async {
      final service = FriendService(firestore: firestore);

      late ValueChanged<String> emit;
      await pumpPage(
        tester,
        service,
        scanViewBuilder: (context, onDetect) {
          emit = onDetect;
          return const ColoredBox(color: Colors.black);
        },
      );
      await openScan(tester);

      emit('https://example.com/not-a-code');
      await tester.pumpAndSettle();

      expect(find.byKey(FriendCodeKeys.scanError), findsOneWidget);
      expect(find.text('Not a Bible Read code.'), findsOneWidget);
    });

    testWidgets('offers typing the code instead from the Scan view',
        (tester) async {
      final service = FriendService(firestore: firestore);

      await pumpPage(
        tester,
        service,
        scanViewBuilder: (context, onDetect) =>
            const ColoredBox(color: Colors.black),
      );
      await openScan(tester);

      await tester.tap(find.byKey(FriendCodeKeys.enterCodeButton));
      await tester.pumpAndSettle();

      expect(find.byKey(JoinCodeKeys.codeField), findsOneWidget);
    });

    testWidgets('a messy payload is normalised before routing', (tester) async {
      final codes = ['MNPQRS23', 'ABCDEFGH'];
      final service = FriendService(
        firestore: firestore,
        generateCode: () => codes.removeAt(0),
      );
      await firestore.collection('users').doc('owner').set({'name': 'Mei'});
      final ownerCode = await service.ensureMyCode('owner');

      late ValueChanged<String> emit;
      await pumpPage(
        tester,
        service,
        scanViewBuilder: (context, onDetect) {
          emit = onDetect;
          return const ColoredBox(color: Colors.black);
        },
      );
      await openScan(tester);

      final messy =
          ' ${ownerCode.substring(0, 4).toLowerCase()} ${ownerCode.substring(4)} ';
      emit(messy);
      await tester.pumpAndSettle();

      expect(find.byKey(FriendCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Add Mei as a friend'), findsOneWidget);
    });
  });
}
