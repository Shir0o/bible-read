import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Initialized once per test file via [initScreenshotBinding].
late IntegrationTestWidgetsFlutterBinding screenshotBinding;

IntegrationTestWidgetsFlutterBinding initScreenshotBinding() {
  screenshotBinding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  return screenshotBinding;
}

/// Captures a screenshot for App Store / Play Store listings.
///
/// Safe to call when running under `flutter test` (no driver attached): the
/// underlying call is a no-op there, so the test still passes.
Future<void> takeScreenshot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  if (Platform.isIOS) {
    await screenshotBinding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
  }
  await screenshotBinding.takeScreenshot(name);
}
