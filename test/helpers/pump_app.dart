import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:google_fonts/google_fonts.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    NavigatorObserver? navigatorObserver,
  }) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await mockNetworkImagesFor(() async {
      await pumpWidget(
        MaterialApp(
          home: widget,
          navigatorObservers:
              navigatorObserver != null ? [navigatorObserver] : [],
        ),
      );
    });
  }
}
