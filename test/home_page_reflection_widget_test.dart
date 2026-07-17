// Tests for the reflections/journaling feature on the Today page (#747): a
// saved-entry card with Edit, or a prompt card that opens the editor sheet.
// Reflections are gated on the daily habit already being marked, and saving/
// skipping must never touch the habit mark, the `reading` doc, or plan
// progress.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'package:bible_read/widgets/reflect_sheet.dart';
import 'helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
      ),
      home: home,
    );

// Real "now" — HomePage's default ReadingStatusService always uses the real
// system clock for the `reading` doc lookup (it isn't threaded through
// widget.dateProvider), so the reflection date basis must match it exactly
// rather than a fixed date.
final _today = DateTime.now();
final _todayKey = '${_today.year}-${_today.month.toString().padLeft(2, '0')}-'
    '${_today.day.toString().padLeft(2, '0')}';
final _todayPrompt = reflectionPromptFor(_today);

Future<void> _markReadToday(FakeFirebaseFirestore firestore) => firestore
    .collection('users')
    .doc('u1')
    .collection('reading')
    .doc(_todayKey)
    .set({'read': true});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets('no reflection card before the habit is marked read',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await tester.pumpWidget(
      _host(HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => _today,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take a moment'), findsNothing);
    expect(find.text(_todayPrompt), findsNothing);
  });

  testWidgets('prompt card appears once the habit is marked read',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await _markReadToday(firestore);

    await tester.pumpWidget(
      _host(HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => _today,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take a moment'), findsOneWidget);
    expect(find.text(_todayPrompt), findsOneWidget);
  });

  testWidgets(
      'saving a reflection writes it and swaps the card to the saved view',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await _markReadToday(firestore);

    await tester.pumpWidget(
      _host(HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => _today,
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take a moment'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Rest isn’t earned here. He makes me lie down.',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Card swaps to the saved view.
    expect(find.text('YOUR REFLECTION'), findsOneWidget);
    expect(
      find.text('Rest isn’t earned here. He makes me lie down.'),
      findsOneWidget,
    );
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Take a moment'), findsNothing);

    // Persisted under its own subcollection, independent of `reading`.
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(_todayKey)
        .get();
    expect(doc.data()?['text'], 'Rest isn’t earned here. He makes me lie down.');

    // The habit mark itself is untouched by the reflection write.
    final readDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(_todayKey)
        .get();
    expect(readDoc.data()?['read'], isTrue);
  });

  testWidgets('skip closes the sheet without writing a reflection',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await _markReadToday(firestore);

    await tester.pumpWidget(
      _host(HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => _today,
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take a moment'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip for today'));
    await tester.pumpAndSettle();

    expect(find.text('Take a moment'), findsOneWidget);

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(_todayKey)
        .get();
    expect(doc.exists, isFalse);
  });

  testWidgets('editing a saved reflection pre-fills the sheet and overwrites it',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await _markReadToday(firestore);
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(_todayKey)
        .set({'text': 'First draft'});

    await tester.pumpWidget(
      _host(HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => _today,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('First draft'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('First draft'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Revised thought');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Revised thought'), findsOneWidget);
    expect(find.text('First draft'), findsNothing);

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(_todayKey)
        .get();
    expect(doc.data()?['text'], 'Revised thought');
  });
}
