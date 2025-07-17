import 'dart:io';
import 'package:fake_firebase_security_rules/fake_firebase_security_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rulesText = File('firestore.rules').readAsStringSync();
  final cleaned = rulesText.split('\n').skip(1).join('\n');
  final rules = FakeFirebaseSecurityRules(cleaned);

  group('friend request rules', () {
    test('sender can write sent and received docs', () {
      const fromUid = 'userA';
      const toUid = 'userB';
      final variables = {
        'request': {
          'auth': {'uid': fromUid}
        }
      };
      expect(
        rules.isAllowed(
          'databases/(default)/documents/users/$fromUid/friendRequestsSent/$toUid',
          Method.write,
          variables: variables,
        ),
        isTrue,
      );
      expect(
        rules.isAllowed(
          'databases/(default)/documents/users/$toUid/friendRequestsReceived/$fromUid',
          Method.write,
          variables: variables,
        ),
        isTrue,
      );
    });

    test('other user cannot write received doc', () {
      const fromUid = 'userA';
      const toUid = 'userB';
      final variables = {
        'request': {
          'auth': {'uid': toUid}
        }
      };
      expect(
        rules.isAllowed(
          'databases/(default)/documents/users/$toUid/friendRequestsReceived/$fromUid',
          Method.write,
          variables: variables,
        ),
        isFalse,
      );
    });
  });
}
