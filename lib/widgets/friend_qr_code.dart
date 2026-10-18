import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The reader's friend code as a scannable QR (ADR-0012 V2, #1005).
///
/// The QR encodes the code alone — no uid, no URL — so it carries nothing the
/// typed code does not already expose. It is drawn black-on-white in both
/// themes so a camera can read it reliably.
class FriendQrCode extends StatelessWidget {
  /// The friend code to encode.
  final String data;

  const FriendQrCode({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      size: 200,
      backgroundColor: Colors.white,
      semanticsLabel: 'Friend code $data',
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }
}
