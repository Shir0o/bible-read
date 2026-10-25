import 'dart:async';
import 'package:bible_read/services/connectivity_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/ambient_sync_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AmbientSyncIndicator', () {
    testWidgets('renders hidden when online with no pending writes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: const Scaffold(
            body: AmbientSyncIndicator(
              initialStatus: ConnectionStatus.online,
              hasPendingWrites: false,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('ambient_sync_hidden')), findsOneWidget);
      expect(find.text('Saved locally'), findsNothing);
      expect(find.text('All synced'), findsNothing);
    });

    testWidgets('renders saved locally pill when initially offline',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: const Scaffold(
            body: AmbientSyncIndicator(
              initialStatus: ConnectionStatus.offline,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('ambient_sync_saved_locally')),
        findsOneWidget,
      );
      expect(find.text('Saved locally'), findsOneWidget);
      expect(find.text('All synced'), findsNothing);
    });

    testWidgets('transitions from offline to online: shows All synced then hides',
        (tester) async {
      final controller = StreamController<ConnectionStatus>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: Scaffold(
            body: AmbientSyncIndicator(
              statusStream: controller.stream,
              initialStatus: ConnectionStatus.online,
              syncedDuration: const Duration(milliseconds: 1000),
            ),
          ),
        ),
      );

      // Initially online
      expect(find.text('Saved locally'), findsNothing);
      expect(find.text('All synced'), findsNothing);

      // Go offline
      controller.add(ConnectionStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // AnimatedSwitcher

      expect(
        find.byKey(const ValueKey('ambient_sync_saved_locally')),
        findsOneWidget,
      );
      expect(find.text('Saved locally'), findsOneWidget);

      // Reconnect online
      controller.add(ConnectionStatus.online);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('ambient_sync_all_synced')),
        findsOneWidget,
      );
      expect(find.text('All synced'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Fast forward past syncedDuration (1000ms) and settle animation
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ambient_sync_hidden')), findsOneWidget);
      expect(find.text('All synced'), findsNothing);
    });

    testWidgets('shows saved locally when hasPendingWrites is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: const Scaffold(
            body: AmbientSyncIndicator(
              initialStatus: ConnectionStatus.online,
              hasPendingWrites: true,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('ambient_sync_saved_locally')),
        findsOneWidget,
      );
      expect(find.text('Saved locally'), findsOneWidget);
    });

    testWidgets('re-going offline cancels synced timer and shows saved locally',
        (tester) async {
      final controller = StreamController<ConnectionStatus>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: Scaffold(
            body: AmbientSyncIndicator(
              statusStream: controller.stream,
              initialStatus: ConnectionStatus.offline,
              syncedDuration: const Duration(milliseconds: 2500),
            ),
          ),
        ),
      );

      expect(find.text('Saved locally'), findsOneWidget);

      // Come online -> All synced
      controller.add(ConnectionStatus.online);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('All synced'), findsOneWidget);

      // Before timer expires (500ms in), go offline again
      await tester.pump(const Duration(milliseconds: 500));
      controller.add(ConnectionStatus.offline);
      await tester.pumpAndSettle();

      expect(find.text('Saved locally'), findsOneWidget);
      expect(find.text('All synced'), findsNothing);
    });
  });
}
