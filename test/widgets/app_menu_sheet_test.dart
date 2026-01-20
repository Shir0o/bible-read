import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/admin/feedback_admin_page.dart';
import 'package:bible_read/services/admin_role_service.dart';
import 'package:bible_read/services/feedback_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

class _StubVibrationService extends VibrationService {
  int calls = 0;

  @override
  Future<void> lightImpact() async {
    calls++;
  }
}

class _AlwaysAdminService extends AdminRoleService {
  _AlwaysAdminService()
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  @override
  Future<bool> isAdmin({bool allowStale = true}) async => true;
}

class _NeverAdminService extends AdminRoleService {
  _NeverAdminService()
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  @override
  Future<bool> isAdmin({bool allowStale = true}) async => false;
}

class _StaleCachedAdminService extends AdminRoleService {
  _StaleCachedAdminService(bool cachedValue)
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore()) {
    primeCacheForTest(
      cachedValue,
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    );
  }

  @override
  Future<bool> fetchAdminRole() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('selecting menu item notifies listener and closes sheet',
      (tester) async {
    final vibrationService = _StubVibrationService();
    int? lastIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    AppMenuSheet.show(
                      context: context,
                      onNavigate: (index) => lastIndex = index,
                      vibrationService: vibrationService,
                      feedbackService: FeedbackService(
                        firestore: FakeFirebaseFirestore(),
                        auth: MockFirebaseAuth(),
                      ),
                      adminRoleService: _NeverAdminService(),
                    );
                  },
                  child: const Text('Open menu'),
                ),
              );
            },
          ),
        ),
      ),
    );

    Future<void> openMenu() async {
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSheet), findsOneWidget);
    }

    Future<void> select(String label, int expectedIndex) async {
      final previousCalls = vibrationService.calls;
      lastIndex = null;
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(lastIndex, expectedIndex);
      expect(vibrationService.calls, previousCalls + 1);
      expect(find.byType(AppMenuSheet), findsNothing);
    }

    await openMenu();
    await select('Leaderboard', 3);

    await openMenu();
    await select('Friends', 4);

    await openMenu();
    await select('Achievements', 6);

    await openMenu();
    await select('Sign Out', 10);
  });

  testWidgets('shows Feedback Inbox entry for admin users', (tester) async {
    final fakeFirestore = FakeFirebaseFirestore();
    final mockAuth = MockFirebaseAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  AppMenuSheet.show(
                    context: context,
                    onNavigate: (_) {},
                    vibrationService: const VibrationService(),
                    feedbackService: FeedbackService(
                      firestore: fakeFirestore,
                      auth: mockAuth,
                    ),
                    adminRoleService: _AlwaysAdminService(),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Feedback Inbox'), findsOneWidget);

    final scrollable = find.descendant(
        of: find.byType(AppMenuSheet), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(
      find.text('Feedback Inbox'),
      200.0,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Feedback Inbox'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackAdminPage), findsOneWidget);
  });

  testWidgets('menu uses cached admin value without waiting for refresh',
      (tester) async {
    final adminRoleService = _StaleCachedAdminService(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  AppMenuSheet.show(
                    context: context,
                    onNavigate: (_) {},
                    vibrationService: const VibrationService(),
                    adminRoleService: adminRoleService,
                  );
                },
                child: const Text('Open menu'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pump();

    expect(find.byType(AppMenuSheet), findsOneWidget);
    expect(find.text('Feedback Inbox'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });
}
