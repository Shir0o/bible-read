import 'dart:io';
import 'package:fake_firebase_security_rules/fake_firebase_security_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseSecurityRules rules;
  const db = 'test-db';

  Map<String, dynamic> auth(String uid) => {
        'request': {
          'auth': {'uid': uid}
        }
      };

  setUpAll(() {
    final rulesLines = File('firestore.rules').readAsLinesSync();
    final filtered = rulesLines
        .where((line) => !line.startsWith('rules_version'))
        .map((line) => line.replaceAll(
            RegExp(r'request\.resource\.data\.keys\(\)\.hasOnly\([^\)]*\)'),
            'true'))
        .map((line) => line.replaceAll('create:', 'write:'))
        .join('\n');
    rules = FakeFirebaseSecurityRules(filtered);
  });

  group('/users', () {
    const base = 'databases/$db/documents/users';

    test('any signed-in user can read profiles', () {
      expect(
          rules.isAllowed('$base/alice', Method.read, variables: auth('bob')),
          isTrue);
    });

    test('owner can write own profile', () {
      expect(
          rules.isAllowed('$base/alice', Method.write,
              variables: auth('alice')),
          isTrue);
    });

    test('cannot write another user profile', () {
      expect(
          rules.isAllowed('$base/alice', Method.write, variables: auth('bob')),
          isFalse);
    });
  });

  group('/friends subcollection', () {
    const base = 'databases/$db/documents/users/alice/friends';

    test('owner can add friends', () {
      expect(
          rules.isAllowed('$base/bob', Method.write, variables: auth('alice')),
          isTrue);
    });

    test('non-owner cannot read friend document', () {
      expect(rules.isAllowed('$base/bob', Method.read, variables: auth('bob')),
          isFalse);
    });
  });

  group('/friendRequestsSent', () {
    const base = 'databases/$db/documents/users/alice/friendRequestsSent/bob';

    test('sender can create request', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isTrue);
    });

    test('other user cannot create request', () {
      expect(
          rules.isAllowed(base, Method.write, variables: auth('bob')), isFalse);
    });

    test('sender can read request', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });
  });

  group('/friendRequestsReceived', () {
    const base =
        'databases/$db/documents/users/bob/friendRequestsReceived/alice';

    test('sender can create incoming request', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isTrue);
    });

    test('receiver can read request', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isTrue);
    });

    test('delete allowed by sender', () {
      expect(rules.isAllowed(base, Method.delete, variables: auth('alice')),
          isTrue);
    });

    test('delete allowed by receiver', () {
      expect(
          rules.isAllowed(base, Method.delete, variables: auth('bob')), isTrue);
    });
  });

  group('/notificationPrefs', () {
    const base = 'databases/$db/documents/users/alice/notificationPrefs/like';

    test('owner can read preference', () {
      expect(rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('owner can write preference', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')), isTrue);
    });

    test('other user cannot read', () {
      expect(rules.isAllowed(base, Method.read, variables: auth('bob')), isFalse);
    });
  });

  group('/read_logs', () {
    const base = 'databases/$db/documents/read_logs/2024-01-01/entries';

    test('any signed-in user can read feed', () {
      expect(
          rules.isAllowed('$base/alice', Method.read, variables: auth('bob')),
          isTrue);
    });

    test('owner can write entry', () {
      expect(
          rules.isAllowed('$base/alice', Method.write,
              variables: auth('alice')),
          isTrue);
    });

    test('other user cannot write entry', () {
      expect(
          rules.isAllowed('$base/alice', Method.write, variables: auth('bob')),
          isFalse);
    });

    test('liker subcollection rules', () {
      final likePath = '$base/alice/likes/bob';
      expect(rules.isAllowed(likePath, Method.read, variables: auth('alice')),
          isTrue);
      expect(rules.isAllowed(likePath, Method.write, variables: auth('bob')),
          isTrue);
      expect(rules.isAllowed(likePath, Method.write, variables: auth('alice')),
          isFalse);
    });
  });

  group('/reading likes', () {
    const base =
        'databases/$db/documents/users/alice/reading/2024-01-01/likes/bob';

    test('owner or liker can read', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isTrue);
    });

    test('other user cannot read', () {
      expect(rules.isAllowed(base, Method.read, variables: auth('charlie')),
          isFalse);
    });

    test('only liker can write', () {
      expect(
          rules.isAllowed(base, Method.write, variables: auth('bob')), isTrue);
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isFalse);
    });
  });
}
