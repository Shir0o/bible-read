import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/widgets/navigation_menu_scope.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:bible_read/services/admin_role_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class _MockAdminRoleService extends Mock implements AdminRoleService {}

class _MockVibrationService extends Mock implements VibrationService {}

class _RecordingVibrationService extends VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NavigationMenuScope.of returns scope and throws when absent',
      (tester) async {
    NavigationMenuScope? capturedScope;

    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMenuScope(
          onNavigate: (_) {},
          friendsIndex: 2,
          child: Builder(
            builder: (context) {
              capturedScope = NavigationMenuScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final scopeWidget = tester.widget<NavigationMenuScope>(
      find.byType(NavigationMenuScope),
    );

    expect(capturedScope, equals(scopeWidget));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => NavigationMenuScope.of(context),
              throwsA(
                isA<FlutterError>().having(
                  (error) => error.message,
                  'message',
                  contains('NavigationMenuScope not found in widget tree.'),
                ),
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  test('updateShouldNotify reacts to property changes', () {
    void onNavigate(int _) {}
    void alternateOnNavigate(int _) {}
    final baseVibration = const VibrationService();
    final differentVibration = _MockVibrationService();
    final baseAdminService = _MockAdminRoleService();
    final differentAdminService = _MockAdminRoleService();

    NavigationMenuScope buildScope({
      ValueChanged<int>? navigate,
      int friendsIndex = 2,
      VibrationService? vibrationService,
      AdminRoleService? adminRoleService,
    }) {
      return NavigationMenuScope(
        onNavigate: navigate ?? onNavigate,
        friendsIndex: friendsIndex,
        vibrationService: vibrationService ?? baseVibration,
        adminRoleService: adminRoleService,
        child: const SizedBox(),
      );
    }

    final baseScope = buildScope(adminRoleService: baseAdminService);

    expect(
      buildScope(
              navigate: alternateOnNavigate, adminRoleService: baseAdminService)
          .updateShouldNotify(baseScope),
      isTrue,
    );
    expect(
      buildScope(friendsIndex: 5, adminRoleService: baseAdminService)
          .updateShouldNotify(baseScope),
      isTrue,
    );
    expect(
      buildScope(
        vibrationService: differentVibration,
        adminRoleService: baseAdminService,
      ).updateShouldNotify(baseScope),
      isTrue,
    );
    expect(
      buildScope(adminRoleService: differentAdminService)
          .updateShouldNotify(baseScope),
      isTrue,
    );

    expect(
      buildScope(adminRoleService: baseAdminService)
          .updateShouldNotify(baseScope),
      isFalse,
    );
  });

  testWidgets('showMenu forwards dependencies to AppMenuSheet', (tester) async {
    final vibrationService = _RecordingVibrationService();
    final adminRoleService = _MockAdminRoleService();
    void onNavigate(int _) {}
    late NavigationMenuScope scope;
    late BuildContext childContext;

    when(() => adminRoleService.cachedAdminRole).thenReturn(false);
    when(() => adminRoleService.isAdmin(allowStale: any(named: 'allowStale')))
        .thenAnswer((_) async => false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenuScope(
            onNavigate: onNavigate,
            friendsIndex: 2,
            vibrationService: vibrationService,
            adminRoleService: adminRoleService,
            child: Builder(
              builder: (context) {
                scope = NavigationMenuScope.of(context);
                childContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final menuFuture = scope.showMenu(childContext);
    await tester.pumpAndSettle();

    final sheet = tester.widget<AppMenuSheet>(find.byType(AppMenuSheet));
    expect(sheet.onNavigate, same(onNavigate));
    expect(sheet.vibrationService, same(vibrationService));
    expect(sheet.adminRoleService, same(adminRoleService));

    Navigator.of(childContext).pop();
    await tester.pumpAndSettle();
    await menuFuture;
  });
}
