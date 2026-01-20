import 'package:bible_read/services/vibration_service.dart';

class StubVibrationService extends VibrationService {
  const StubVibrationService();

  @override
  Future<void> lightImpact() async {}
  
  @override
  Future<void> tap() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> heavyImpact() async {}
}
