import 'package:bible_read/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

extension PumpGolden on WidgetTester {
  Future<void> pumpGolden(
    Widget widget, {
    Brightness brightness = Brightness.light,
    double textScaleFactor = 1.0,
    Size surfaceSize = const Size(800, 600),
  }) async {
    // Configure tolerance for pixel comparison to handle CI vs Local rendering differences.
    _configureGoldenComparator();

    // Set surface size
    await binding.setSurfaceSize(surfaceSize);
    addTearDown(() => binding.setSurfaceSize(null));

    await mockNetworkImagesFor(() async {
      await pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.appTheme(AppTheme.seededColorScheme(brightness)),
          home: MediaQuery(
            data: MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(textScaleFactor),
              platformBrightness: brightness,
            ),
            child: Scaffold(
              backgroundColor: AppTheme.seededColorScheme(brightness).surface,
              body: Center(
                child: widget,
              ),
            ),
          ),
        ),
      );
    });
  }

  void _configureGoldenComparator() {
    if (goldenFileComparator is LocalFileComparator) {
      final comparator = goldenFileComparator as LocalFileComparator;
      // Wrap the comparator if it hasn't been wrapped already.
      if (comparator is! LocalFileComparatorWithThreshold) {
        // LocalFileComparator expects a file URI and calculates the basedir from it.
        // We pass a dummy file within the current basedir to ensure the new comparator
        // maintains the correct directory context.
        final testFile = comparator.basedir.resolve('dummy_for_config.dart');
        goldenFileComparator = LocalFileComparatorWithThreshold(
          testFile,
          0.015, // 1.5% tolerance for local vs CI font rasterization variance.
        );
      }
    }
  }
}

/// A custom [LocalFileComparator] that allows a configurable difference threshold.
class LocalFileComparatorWithThreshold extends LocalFileComparator {
  final double threshold;

  LocalFileComparatorWithThreshold(super.testFile, this.threshold)
      : assert(threshold >= 0 && threshold <= 1);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed) {
      return true;
    }

    if (!result.passed && result.diffPercent <= threshold) {
      debugPrint(
        'Golden file difference of ${(result.diffPercent * 100).toStringAsFixed(2)}% '
        'is within the threshold of ${(threshold * 100).toStringAsFixed(2)}%. Passing.',
      );
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
