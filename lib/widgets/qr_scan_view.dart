import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

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

/// The scanning frame drawn over the camera: four corner brackets and a hint.
///
/// Shared by the add-code screen so a code is easy to line up whatever entry
/// point opened it.
class QrScanFrame extends StatelessWidget {
  /// Hint shown under the brackets.
  final String hint;

  const QrScanFrame({super.key, this.hint = 'Point at their code'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              children: [
                for (final alignment in [
                  Alignment.topLeft,
                  Alignment.topRight,
                  Alignment.bottomLeft,
                  Alignment.bottomRight,
                ])
                  Align(
                    alignment: alignment,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border(
                          top: alignment.y < 0
                              ? const BorderSide(color: Colors.white, width: 4)
                              : BorderSide.none,
                          bottom: alignment.y > 0
                              ? const BorderSide(color: Colors.white, width: 4)
                              : BorderSide.none,
                          left: alignment.x < 0
                              ? const BorderSide(color: Colors.white, width: 4)
                              : BorderSide.none,
                          right: alignment.x > 0
                              ? const BorderSide(color: Colors.white, width: 4)
                              : BorderSide.none,
                        ),
                        borderRadius: BorderRadius.circular(AppSpacing.rChip),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),
          // token-exempt: white hint over the dark camera preview
          Text(hint,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
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
