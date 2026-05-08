import 'package:bible_read/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    NavigatorObserver? navigatorObserver,
  }) async {
    await mockNetworkImagesFor(() async {
      await pumpWidget(
        MaterialApp(
          theme:
              AppTheme.appTheme(AppTheme.seededColorScheme(Brightness.light)),
          darkTheme:
              AppTheme.appTheme(AppTheme.seededColorScheme(Brightness.dark)),
          home: widget,
          navigatorObservers:
              navigatorObserver != null ? [navigatorObserver] : [],
        ),
      );
    });
  }
}
