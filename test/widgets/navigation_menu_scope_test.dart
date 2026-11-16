import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/widgets/navigation_menu_scope.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:bible_read/services/vibration_service.dart';

class _MockVibrationService extends Mock implements VibrationService {}

class _RecordingVibrationService extends VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NavigationMenuScope.of returns scope and throws when absent', (
    tester,
  ) async {
    NavigationMenuScope? capturedScope;

    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMenuScope(
          onNavigate: (_) {},
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

    NavigationMenuScope buildScope({
      ValueChanged<int>? navigate,
      VibrationService? vibrationService,
    }) {
      return NavigationMenuScope(
        onNavigate: navigate ?? onNavigate,
        vibrationService: vibrationService ?? baseVibration,
        child: const SizedBox(),
      );
    }

    final baseScope = buildScope();

    expect(
      buildScope(
        navigate: alternateOnNavigate,
      ).updateShouldNotify(baseScope),
      isTrue,
    );
    expect(
      buildScope(
        vibrationService: differentVibration,
      ).updateShouldNotify(baseScope),
      isTrue,
    );

    expect(
      buildScope().updateShouldNotify(baseScope),
      isFalse,
    );
  });

  testWidgets('showMenu forwards dependencies to AppMenuSheet', (tester) async {
    final vibrationService = _RecordingVibrationService();
    late NavigationMenuScope scope;
    late BuildContext childContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenuScope(
            onNavigate: (_) {},
            vibrationService: vibrationService,
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
    expect(sheet.vibrationService, same(vibrationService));

    Navigator.of(childContext).pop();
    await tester.pumpAndSettle();
    await menuFuture;
  });
}
