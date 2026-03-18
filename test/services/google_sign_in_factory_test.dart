import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('createGoogleSignIn returns a singleton instance', () {
    final instance1 = createGoogleSignIn();
    final instance2 = createGoogleSignIn();

    expect(instance1, same(instance2));
    expect(instance1, isA<GoogleSignIn>());
  });
}
