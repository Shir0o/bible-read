// The Home "Your community" glimpse is sourced from the reader's Circle —
// the co-members of their Groups, derived at read time (ADR-0003, #795).
// There is no friend graph to consult.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme:
          ThemeData(useMaterial3: true, splashFactory: NoSplash.splashFactory),
      home: home,
    );

Future<void> _seedGroup(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String ownerUid,
  List<String> members = const [],
}) async {
  await firestore.collection('groups').doc(id).set({
    'name': 'Group $id',
    'ownerUid': ownerUid,
    'memberCount': members.length + 1,
  });
  await firestore
      .collection('groups')
      .doc(id)
      .collection('members')
      .doc(ownerUid)
      .set({'uid': ownerUid, 'role': 'owner'});
  for (final uid in members) {
    await firestore
        .collection('groups')
        .doc(id)
        .collection('members')
        .doc(uid)
        .set({'uid': uid, 'role': 'member'});
  }
}

Future<void> _seedReadToday(
  FakeFirebaseFirestore firestore, {
  required String uid,
  required String name,
  required DateTime day,
  required List<String> groupIds,
}) async {
  final dateKey =
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  for (final groupId in groupIds) {
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('read_log')
        .doc(dateKey)
        .collection('entries')
        .doc(uid)
        .set({'uid': uid, 'name': name, 'dateId': dateKey});
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
  MockFirebaseAuth auth,
) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _host(
      HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: DateTime.now,
        enableDriftAnimation: false,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Dismiss the auto-opened check-in to see the page.
  final checkIn = find.text('Did you read today?');
  if (tester.any(checkIn)) {
    await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets('glimpse counts co-members from Groups, not strangers', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u2'),
      signedIn: true,
    );
    final today = DateTime.now();

    // u2 shares two Groups; u1 is in both and must appear once.
    await _seedGroup(firestore,
        id: 'g1', ownerUid: 'u1', members: ['u2', 'u3']);
    await _seedGroup(firestore,
        id: 'g2', ownerUid: 'u4', members: ['u2', 'u1']);
    // The reader (u2) is in both Groups; u3 only shares g1; the stranger's
    // entry lives in a Group u2 does not belong to and must never surface.
    await _seedReadToday(firestore,
        uid: 'u2', name: 'You', day: today, groupIds: ['g1', 'g2']);
    await _seedReadToday(firestore,
        uid: 'u3', name: 'Miriam', day: today, groupIds: ['g1']);
    await _seedReadToday(firestore,
        uid: 'u9', name: 'Stranger', day: today, groupIds: ['g9']);

    await _pumpHome(tester, firestore, auth);

    expect(find.text('Your community'), findsOneWidget);
    expect(find.text('2 of 4 read today'), findsOneWidget);
    expect(find.textContaining('Stranger'), findsNothing);
  });

  testWidgets('a reader in no Groups still sees the glimpse, not an error', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await _pumpHome(tester, firestore, auth);

    expect(find.text('Your community'), findsOneWidget);
    expect(find.text('0 of 1 read today'), findsOneWidget);
    expect(find.text('Be the first to show up today'), findsOneWidget);
  });
}
