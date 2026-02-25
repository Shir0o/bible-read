import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_image_mock/network_image_mock.dart';

extension PumpGolden on WidgetTester {
  Future<void> pumpGolden(
    Widget widget, {
    Brightness brightness = Brightness.light,
    double textScaleFactor = 1.0,
    Size surfaceSize = const Size(800, 600),
  }) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    // Set surface size
    await binding.setSurfaceSize(surfaceSize);
    addTearDown(() => binding.setSurfaceSize(null));

    await mockNetworkImagesFor(() async {
      await pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: brightness,
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(textScaleFactor),
              platformBrightness: brightness,
            ),
            child: Scaffold(
              backgroundColor: brightness == Brightness.light
                  ? Colors.white
                  : Colors.black,
              body: Center(
                child: widget,
              ),
            ),
          ),
        ),
      );
    });
  }
}
