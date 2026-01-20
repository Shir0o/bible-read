import 'package:bible_read/services/error_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

class _EmptyFirebasePlatform extends FirebasePlatform {
  @override
  List<FirebaseAppPlatform> get apps => [];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) {
    throw UnimplementedError();
  }
}

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

  test('log does not call Crashlytics when Firebase is uninitialized',
      () async {
    final original = Firebase.delegatePackingProperty;
    Firebase.delegatePackingProperty = _EmptyFirebasePlatform();
    // Clear the crashlytics mock to simulate uninitialized state
    ErrorLogger.crashlytics = null;
    addTearDown(() {
      Firebase.delegatePackingProperty = original;
      // Restore the mock for other tests (though setUp runs before each test anyway)
      ErrorLogger.crashlytics = mock;
    });

    await ErrorLogger.log(Exception('boom'), StackTrace.current);

    verifyNever(
      () => mock.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        information: any(named: 'information'),
        printDetails: any(named: 'printDetails'),
        fatal: any(named: 'fatal'),
      ),
    );
  });

  test('log swallows errors from Crashlytics.recordError', () async {
    final error = Exception('boom');
    final stack = StackTrace.current;

    when(() => mock.recordError(
          error,
          stack,
          reason: null,
          information: const [],
          printDetails: null,
          fatal: false,
        )).thenThrow(Exception('fail'));

    await expectLater(ErrorLogger.log(error, stack), completes);

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
