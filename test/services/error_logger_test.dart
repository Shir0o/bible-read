import 'package:bible_read/services/error_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late MockCrashlytics mock;

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    mock = MockCrashlytics();
    ErrorLogger.crashlytics = mock;
  });

  test('log calls Crashlytics.recordError', () async {
    final error = Exception('boom');
    final stack = StackTrace.current;

    when(() => mock.recordError(
          error,
          stack,
          reason: null,
          information: const [],
          printDetails: null,
          fatal: false,
        )).thenAnswer((_) async {});

    await ErrorLogger.log(error, stack);

    verify(() => mock.recordError(
          error,
          stack,
          reason: null,
          information: const [],
          printDetails: null,
          fatal: false,
        )).called(1);
  });
}
