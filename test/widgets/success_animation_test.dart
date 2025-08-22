import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/success_animation.dart';
import 'package:bible_read/services/vibration_service.dart';

class _RecordingVibrationService extends VibrationService {
  int mediumCount = 0;

  @override
  Future<void> mediumImpact() async {
    mediumCount++;
  }
}

class _ErrorHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Future<HttpClientRequest>.error(const SocketException(''));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future<HttpClientRequest>.error(const SocketException(''));
}

void main() {
  testWidgets('shows fallback icon when animation fails to load', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SuccessAnimation(onDismiss: () {})),
        ),
      );
      await tester.pump();
      await tester.pump();
    }, createHttpClient: (_) => _ErrorHttpClient());

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('invokes vibration when shown', (tester) async {
    final service = _RecordingVibrationService();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await SuccessAnimation.show(
      tester.element(find.byType(Scaffold)),
      vibrationService: service,
    );
    await tester.pump();
    expect(service.mediumCount, 1);
  });
}
