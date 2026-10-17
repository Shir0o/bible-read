import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/theme/app_theme.dart';

import '../helpers/pump_golden.dart';
import '../helpers/stub_vibration_service.dart';

/// Registers the app's bundled faces so golden text renders as type rather
/// than as the test framework's placeholder boxes.
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Spectral', [
    'Spectral-Regular.ttf',
    'Spectral-Medium.ttf',
    'Spectral-SemiBold.ttf',
  ]);
  await load('Hanken Grotesk', ['HankenGrotesk-VariableFont_wght.ttf']);
}

void main() {
  setUpAll(_loadAppFonts);

  // The New plan page as rebuilt to the third-pass mock (#988), tall enough
  // to show every section, the preview line and the pinned button.
  testWidgets('CreatePlanPage golden', (tester) async {
    // The preview line names today's end date, so allow the same small
    // tolerance the other goldens use rather than pinning the clock.
    final comparator = goldenFileComparator;
    if (comparator is LocalFileComparator &&
        comparator is! LocalFileComparatorWithThreshold) {
      goldenFileComparator = LocalFileComparatorWithThreshold(
        comparator.basedir.resolve('create_plan_golden_test.dart'),
        0.015,
      );
      addTearDown(() => goldenFileComparator = comparator);
    }
    await tester.binding.setSurfaceSize(const Size(390, 1320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: CreatePlanPage(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(signedIn: true),
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CreatePlanPage),
      matchesGoldenFile('create_plan_page.png'),
    );
  });
}
