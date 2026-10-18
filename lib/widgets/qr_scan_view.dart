import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Builds the camera view that scans QR codes, reporting each recognised
/// payload through `onDetect`.
///
/// Injected into the Scan screen so tests can supply a fake scanner instead of
/// a real camera (ADR-0012 V2, #1005).
typedef QrScanViewBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onDetect,
);

/// The real camera scanner, backed by `mobile_scanner`.
Widget cameraQrScanView(BuildContext context, ValueChanged<String> onDetect) {
  return MobileScanner(
    onDetect: (capture) {
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (value != null && value.trim().isNotEmpty) {
          onDetect(value);
          return;
        }
      }
    },
    placeholderBuilder: (context) => const ColoredBox(color: Colors.black),
    errorBuilder: (context, error) => const _CameraUnavailable(),
  );
}

/// Shown when the camera cannot start (denied permission, no camera), so the
/// reader is never stuck: the typed flow is always one tap away.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Camera unavailable. Enter the code instead.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
