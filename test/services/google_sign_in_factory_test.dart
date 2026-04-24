import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockGoogleSignInPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GoogleSignInPlatform {}

class FakeInitParameters extends Fake implements InitParameters {}

void main() {
  late MockGoogleSignInPlatform mockPlatform;

  setUpAll(() {
    registerFallbackValue(FakeInitParameters());
  });

  setUp(() {
    mockPlatform = MockGoogleSignInPlatform();
    GoogleSignInPlatform.instance = mockPlatform;
    when(() => mockPlatform.init(any())).thenAnswer((_) async {});
  });

  test('createGoogleSignIn returns a singleton instance', () {
    final instance1 = createGoogleSignIn();
    final instance2 = createGoogleSignIn();

    expect(instance1, same(instance2));
    expect(instance1, isA<GoogleSignIn>());
  });
}
