import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/pages/add_read_through_page.dart';
import 'package:bible_read/pages/read_throughs_page.dart';
import 'package:bible_read/services/read_through_service.dart';
import 'package:bible_read/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReadThroughService service;
  const uid = 'u1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: uid), signedIn: true);
    service = ReadThroughService(firestore: firestore);
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: child,
      );

  Widget historyPage() => wrap(
        ReadThroughsPage(firestore: firestore, auth: auth, service: service),
      );

  group('ReadThroughsPage', () {
    testWidgets('shows an empty state before anything is finished',
        (tester) async {
      await tester.pumpWidget(historyPage());
      await tester.pumpAndSettle();

      expect(find.text('No times through yet.'), findsOneWidget);
      expect(find.text('Add a past read-through'), findsOneWidget);
    });

    testWidgets('counts each scope, with the whole Bible derived',
        (tester) async {
      await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2025, 1, 1),
      );
      await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2026, 1, 1),
      );
      await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2026, 6, 1),
      );

      await tester.pumpWidget(historyPage());
      await tester.pumpAndSettle();

      expect(find.text('Whole Bible'), findsWidgets);
      expect(find.text('DERIVED'), findsOneWidget);
      // NT 2, OT 1 -> one whole Bible, and the OT lap is now 2.
      expect(find.text('on lap 2'), findsOneWidget);
      expect(find.text('on lap 3'), findsOneWidget);
    });

    testWidgets('lists newest first and marks hand-entered records',
        (tester) async {
      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2011),
        precision: DatePrecision.year,
        location: 'Fuller, Pasadena',
      );
      await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2026, 9, 5),
      );

      await tester.pumpWidget(historyPage());
      await tester.pumpAndSettle();

      expect(find.text('ADDED'), findsOneWidget);
      expect(find.text('2011 · Fuller, Pasadena'), findsOneWidget);
      expect(find.text('Old Testament · 1st time'), findsOneWidget);
      expect(find.text('New Testament · 1st time'), findsOneWidget);
    });

    testWidgets('the add row opens the form', (tester) async {
      await tester.pumpWidget(historyPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a past read-through'));
      await tester.pumpAndSettle();

      expect(find.byType(AddReadThroughPage), findsOneWidget);
      expect(find.text('A past read-through'), findsOneWidget);
    });
  });

  group('AddReadThroughPage', () {
    Widget formPage({ReadThrough? existing}) => wrap(
          AddReadThroughPage(
            firestore: firestore,
            auth: auth,
            service: service,
            existing: existing,
          ),
        );

    testWidgets('says plainly that past entries never reach the feed',
        (tester) async {
      await tester.pumpWidget(formPage());
      await tester.pumpAndSettle();

      // The note sits below the fold on a small surface.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('never posted to the feed'),
        findsOneWidget,
      );
    });

    testWidgets('changing precision changes how the date reads',
        (tester) async {
      await tester.pumpWidget(formPage());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Only remember the year'),
        findsOneWidget,
      );

      await tester.tap(find.text('Exact date'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('the day you read the last chapter'),
        findsOneWidget,
      );
    });

    testWidgets('saving a whole-Bible entry records both testaments',
        (tester) async {
      await tester.pumpWidget(formPage());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Taipei');
      await tester.tap(find.text('Add to my history'));
      await tester.pumpAndSettle();

      final rows = await service.fetchAll(uid);
      final counts = ReadThroughService.countsFrom(rows);
      expect(counts.oldTestament, 1);
      expect(counts.newTestament, 1);
      expect(counts.wholeBible, 1);
      expect(rows.every((r) => r.location == 'Taipei'), isTrue);
    });

    testWidgets('a detected record offers no way to delete it', (tester) async {
      final created = await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2026, 9, 5),
      );

      await tester.pumpWidget(formPage(existing: created.first));
      await tester.pumpAndSettle();

      expect(find.text('Remove from my history'), findsNothing);
      expect(find.text('Save changes'), findsOneWidget);
      // The scope is the app's own account of what happened, not editable.
      expect(find.text('What did you finish?'.toUpperCase()), findsNothing);
    });

    testWidgets('a hand-entered record can be removed', (tester) async {
      final created = await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2011),
        precision: DatePrecision.year,
      );

      await tester.pumpWidget(formPage(existing: created.first));
      await tester.pumpAndSettle();

      expect(find.text('Remove from my history'), findsOneWidget);
    });

    testWidgets('editing saves a new location', (tester) async {
      final created = await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2026, 9, 5),
      );

      await tester.pumpWidget(formPage(existing: created.first));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Taipei');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final rows = await service.fetchAll(uid);
      final nt = rows.firstWhere(
        (r) => r.scope == ReadThroughScope.newTestament,
      );
      expect(nt.location, 'Taipei');
    });
  });
}
