import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';

class _MockPrefsService extends NotificationPreferencesService {
  final bool enabled;
  _MockPrefsService(this.enabled) : super(firestore: FakeFirebaseFirestore());

  @override
  Future<bool> fetchVibrationEnabled(String uid) async => enabled;
}

class _FakeVibrationPlatform extends VibrationPlatform {
  bool vibrated = false;

  @override
  Future<bool> hasVibrator() async => true;

  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
    double sharpness = 0.5,
  }) async {
    vibrated = true;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vibrates when enabled', () async {
    final platform = _FakeVibrationPlatform();
    VibrationPlatform.instance = platform;

    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final service = VibrationService(
      auth: auth,
      prefsService: _MockPrefsService(true),
    );
    await service.lightImpact();
    expect(platform.vibrated, isTrue);
  });

  test('does not vibrate when disabled', () async {
    final platform = _FakeVibrationPlatform();
    VibrationPlatform.instance = platform;

    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final service = VibrationService(
      auth: auth,
      prefsService: _MockPrefsService(false),
    );
    await service.lightImpact();
    expect(platform.vibrated, isFalse);
  });
}
