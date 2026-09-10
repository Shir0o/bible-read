import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/reflection_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';

import 'package:network_image_mock/network_image_mock.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

/// Sharing a Reflection, end to end (#807): the reflect sheet's per-entry
/// toggle decides while the words are in view; sharing copies the text onto
/// the author's read-log entry — the object co-members already read — so the
/// private document stays owner-only. Unsharing removes the copy; editing a
/// shared entry updates it without unsharing. Showing up is never touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });
  tearDownAll(resetHttpOverrides);

  final today = DateTime(2026, 9, 8);
  final todayKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late FirebaseSeeder seeder;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', displayName: 'Alice'),
      signedIn: true,
    );
    seeder = FirebaseSeeder(firestore);
  });

  Future<void> markReadToday() => firestore
      .collection('users')
      .doc('alice')
      .collection('reading')
      .doc(todayKey)
      .set({'read': true});

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            useMaterial3: true, splashFactory: NoSplash.splashFactory),
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          dateProvider: () => today,
          // The status service defaults to DateTime.now; freeze it to the
          // seeded date so "today" matches the seeded read doc.
          readingStatusService: ReadingStatusService(
            firestore: firestore,
            auth: auth,
            nowProvider: () => today,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCircle(WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityPage(
            auth: auth,
            firestore: firestore,
            groupService: GroupService(firestore: firestore),
            readingStatusService: ReadingStatusService(
              firestore: firestore,
              auth: auth,
            ),
            vibrationService: const StubVibrationService(),
            nudgeService: NudgeService(firestore: firestore),
            dateProvider: () => today,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  /// Seeds today's Showing-up entry in every Group of [uids], exactly as
  /// ReadLogService.mark does.
  Future<void> seedShowingUp(Iterable<String> uids,
      {String group = 'g1'}) async {
    for (final uid in uids) {
      await firestore
          .collection('groups')
          .doc(group)
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'dateId': todayKey,
        'timestamp': Timestamp.fromDate(DateTime(2026, 9, 8, 7)),
      });
    }
  }

  testWidgets(
    'Reflect Scenario: the toggle is off for a new Reflection, on while '
    'editing a shared one, and the supporting line names the audience',
    (tester) async {
      await markReadToday();
      await pumpHome(tester);

      // Fresh entry: toggle off, with the supporting line naming who reads.
      await tester.tap(find.text('Take a moment'));
      await tester.pumpAndSettle();

      bool toggleValue() => tester
          .widget<Switch>(
            find.byKey(const ValueKey('reflect_sheet_share_switch')),
          )
          .value;
      expect(toggleValue(), isFalse,
          reason: 'a new Reflection always starts unshared');
      expect(
          find.textContaining('Off — only you can read this.'), findsOneWidget);
      expect(
          find.textContaining('people you share a group with'), findsOneWidget);

      // Turn it on: the line states the current state.
      await tester.enterText(find.byType(TextField), 'A line worth sharing.');
      await tester
          .tap(find.byKey(const ValueKey('reflect_sheet_share_switch')));
      await tester.pump();
      expect(toggleValue(), isTrue);
      expect(
          find.textContaining('On — the people you read with'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Persisted shared state: private doc marks shared, the copy rides on
      // the read-log entry.
      final private = await firestore
          .collection('users')
          .doc('alice')
          .collection('reflections')
          .doc(todayKey)
          .get();
      expect(private.data()?['shared'], isTrue);

      // Editing the shared entry opens with the toggle still on — editing
      // must not unshare.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(toggleValue(), isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Reflect Scenario: a shared Reflection appears on the author\'s row and '
    'a co-member\'s view of it, marked as shared; unshared text appears nowhere',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedGroup(
        groupId: 'g1',
        ownerUid: 'alice',
        name: 'Morning',
        members: ['alice', 'bob'],
      );
      // Members docs need the uid field for the collectionGroup lookup
      // ReflectionService uses to fan out the shared copy.
      for (final member in ['alice', 'bob']) {
        await firestore
            .collection('groups')
            .doc('g1')
            .collection('members')
            .doc(member)
            .set({
          'uid': member,
          'role': member == 'alice' ? 'owner' : 'member',
        });
      }
      await seedShowingUp(['alice', 'bob']);

      // Alice writes privately first: it appears on no row.
      final service = ReflectionService(firestore: firestore);
      await service.saveReflection(
        'alice',
        todayKey,
        'A private first thought.',
      );

      await pumpCircle(tester);
      expect(find.text('A private first thought.'), findsNothing);
      expect(find.textContaining('Shared reflection'), findsNothing);
      // A row with no shared Reflection still renders complete.
      expect(find.text('Showed up'), findsWidgets);

      // Sharing copies it onto the read-log entry: Alice's own row shows it
      // (CommunityPage renders the reader's own row too).
      await service.saveReflection(
        'alice',
        todayKey,
        'A line worth sharing.',
        share: true,
      );
      final entry = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('alice')
          .get();
      expect(entry.data()?['sharedReflection'], 'A line worth sharing.');

      await pumpCircle(tester);
      expect(find.text('A line worth sharing.'), findsOneWidget);
      expect(find.text('Shared reflection'), findsOneWidget);

      // Unsharing removes the copy promptly and leaves the private original.
      await service.saveReflection(
        'alice',
        todayKey,
        'A line worth sharing.',
        share: false,
      );
      final after = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('alice')
          .get();
      expect(after.data()?['sharedReflection'], isNull);

      await pumpCircle(tester);
      expect(find.text('A line worth sharing.'), findsNothing);
      expect(find.text('Shared reflection'), findsNothing);

      final original = await service.fetchReflection('alice', todayKey);
      expect(original?.text, 'A line worth sharing.',
          reason: 'unsharing never touches the private original');
      expect(original?.shared, isFalse);
    },
  );

  testWidgets(
    'Reflect Scenario: editing a shared Reflection updates the shared copy '
    'and keeps it shared; skipping stays possible throughout',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedGroup(
        groupId: 'g1',
        ownerUid: 'alice',
        name: 'Morning',
        members: ['alice'],
      );
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('alice')
          .set({'uid': 'alice', 'role': 'owner'});
      await seedShowingUp(['alice']);

      final service = ReflectionService(firestore: firestore);
      await service.saveReflection('alice', todayKey, 'First draft.',
          share: true);

      // Edit-while-shared: the copy updates, the state stays shared.
      await service.saveReflection('alice', todayKey, 'Revised thought.',
          share: true);
      final entry = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('alice')
          .get();
      expect(entry.data()?['sharedReflection'], 'Revised thought.');
      expect(
          (await service.fetchReflection('alice', todayKey))?.shared, isTrue);

      // The Showing-up mark survives every one of these writes.
      final finalEntry = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('alice')
          .get();
      expect(finalEntry.data()?['dateId'], todayKey);
      expect(finalEntry.data()?['uid'], 'alice');
    },
  );

  testWidgets(
    'Reflect Scenario: skipping a Reflection never touches the Showing-up mark',
    (tester) async {
      await markReadToday();
      await pumpHome(tester);

      await tester.tap(find.text('Take a moment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip for today'));
      await tester.pumpAndSettle();

      // The habit mark is exactly where it was.
      final readDoc = await firestore
          .collection('users')
          .doc('alice')
          .collection('reading')
          .doc(todayKey)
          .get();
      expect(readDoc.data()?['read'], isTrue);
      final reflectionDoc = await firestore
          .collection('users')
          .doc('alice')
          .collection('reflections')
          .doc(todayKey)
          .get();
      expect(reflectionDoc.exists, isFalse);
    },
  );
}
