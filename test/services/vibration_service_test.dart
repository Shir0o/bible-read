import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';

class _MockPrefsService extends NotificationPreferencesService {
  final bool enabled;
  _MockPrefsService(this.enabled) : super(firestore: FakeFirebaseFirestore());

  @override
  Future<bool> fetchVibrationEnabled(String uid) async => enabled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vibration');

  test('vibrates when enabled', () async {
    var vibrated = false;
    channel.setMockMethodCallHandler((methodCall) async {
      if (methodCall.method == 'hasVibrator') return true;
      if (methodCall.method == 'vibrate') vibrated = true;
      return null;
    });

    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final service = VibrationService(
      auth: auth,
      prefsService: _MockPrefsService(true),
    );
    await service.lightImpact();
    expect(vibrated, isTrue);
    channel.setMockMethodCallHandler(null);
  });

  test('does not vibrate when disabled', () async {
    var vibrated = false;
    channel.setMockMethodCallHandler((methodCall) async {
      if (methodCall.method == 'hasVibrator') return true;
      if (methodCall.method == 'vibrate') vibrated = true;
      return null;
    });

    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final service = VibrationService(
      auth: auth,
      prefsService: _MockPrefsService(false),
    );
    await service.lightImpact();
    expect(vibrated, isFalse);
    channel.setMockMethodCallHandler(null);
  });
}
