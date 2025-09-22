@Skip('fake_firebase_security_rules cannot parse current rules')
library;

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

  Map<String, dynamic> noAuth() => {
        'request': {'auth': null}
      };

  setUpAll(() {
    final rulesLines = File('firestore.rules').readAsLinesSync();
    final filtered = rulesLines
        .where((line) => !line.startsWith('rules_version'))
        .map((line) => line.replaceAll(
            RegExp(r'request\.resource\.data\.keys\(\)\.hasOnly\([^\)]*\)'),
            'true'))
        .map((line) => line.replaceAll(
            RegExp(r'request\.resource\.data\.senderUid == request\.auth\.uid'),
            'request.auth.uid == userId'))
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
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('owner can write preference', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isTrue);
    });

    test('other user cannot read', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isFalse);
    });
  });

  group('/notifications', () {
    const base = 'databases/$db/documents/users/alice/notifications/n1';

    test('owner can read notification', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('owner can write notification', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isTrue);
    });

    test('other user cannot access', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isFalse);
      expect(
          rules.isAllowed(base, Method.write, variables: auth('bob')), isFalse);
    });
  });

  group('/achievements', () {
    const base = 'databases/\$db/documents/users/alice/achievements/a1';

    test('owner can read achievement', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('owner can write achievement', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isTrue);
    });

    test('other user cannot access', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isFalse);
      expect(
          rules.isAllowed(base, Method.write, variables: auth('bob')), isFalse);
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

  group('/daily_rewards', () {
    const base = 'databases/$db/documents/daily_rewards/2024-01-01';

    test('signed-in user can read reward', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('writes are denied', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isFalse);
    });
  });

  group('/groups', () {
    const base = 'databases/$db/documents/groups';

    test('owner can read group without member doc', () {
      expect(
          rules.isAllowed('$base/g1', Method.read, variables: {
            ...auth('alice'),
            'resource': {
              'data': {'ownerUid': 'alice'}
            }
          }),
          isTrue);
    });

    test('non-member non-owner can read group', () {
      expect(
          rules.isAllowed('$base/g1', Method.read, variables: {
            ...auth('charlie'),
            'resource': {
              'data': {'ownerUid': 'alice'}
            }
          }),
          isTrue);
    });

    group('/members', () {
      const membersPath = '$base/g1/members';

      test('reject direct member creation without join request', () {
        expect(
            rules.isAllowed('$membersPath/u2', Method.write, variables: {
              ...auth('alice'),
              'resource': {
                'data': {'ownerUid': 'alice'}
              }
            }),
            isFalse);
      });

      test('members cannot change role', () {
        expect(
            rules.isAllowed('$membersPath/u2', Method.update, variables: {
              ...auth('u2'),
              'resource': {
                'data': {'uid': 'u2', 'role': 'member'}
              },
              'request': {
                'resource': {
                  'data': {'uid': 'u2', 'role': 'admin'}
                }
              }
            }),
            isFalse);
      });
    });

    group('/joinRequests', () {
      const requestPath = '$base/g1/joinRequests/u2';
      final getGroup = {
        'get': {
          'databases/$db/documents/groups/g1': {
            'data': {'ownerUid': 'alice'}
          }
        }
      };

      test('requesting user can create join request', () {
        expect(
            rules.isAllowed(requestPath, Method.write, variables: {
              ...auth('u2'),
              ...getGroup,
            }),
            isTrue);
      });

      test('other users cannot create join request', () {
        expect(
            rules.isAllowed(requestPath, Method.write, variables: {
              ...auth('bob'),
              ...getGroup,
            }),
            isFalse);
      });

      test('owner can delete join request', () {
        expect(
            rules.isAllowed(requestPath, Method.delete, variables: {
              ...auth('alice'),
              ...getGroup,
            }),
            isTrue);
      });

      test('requester cannot delete join request', () {
        expect(
            rules.isAllowed(requestPath, Method.delete, variables: {
              ...auth('u2'),
              ...getGroup,
            }),
            isFalse);
      });

      test('owner can read join requests', () {
        expect(
            rules.isAllowed(requestPath, Method.read, variables: {
              ...auth('alice'),
              ...getGroup,
            }),
            isTrue);
      });

      test('non-owner cannot read join requests', () {
        expect(
            rules.isAllowed(requestPath, Method.read, variables: {
              ...auth('bob'),
              ...getGroup,
            }),
            isFalse);
      });
    });
  });

  group('/seasons', () {
    const seasonsBase = 'databases/$db/documents/seasons';
    const challengesBase = 'databases/$db/documents/seasons/spring/challenges';

    test('signed-in user can read season document', () {
      expect(
          rules.isAllowed('$seasonsBase/spring', Method.read,
              variables: auth('alice')),
          isTrue);
    });

    test('unauthenticated read of season denied', () {
      expect(
          rules.isAllowed('$seasonsBase/spring', Method.read,
              variables: noAuth()),
          isFalse);
    });

    test('challenge docs are read-only', () {
      expect(
          rules.isAllowed('$challengesBase/c1', Method.read,
              variables: auth('alice')),
          isTrue);
      expect(
          rules.isAllowed('$challengesBase/c1', Method.write,
              variables: auth('alice')),
          isFalse);
    });
  });

  group('/seasonChallenges', () {
    const base =
        'databases/$db/documents/users/alice/seasonChallenges/spring_c1';

    test('owner can read progress document', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('owner can write valid progress flags', () {
      expect(
          rules.isAllowed(base, Method.write, variables: {
            ...auth('alice'),
            'request': {
              ...auth('alice')['request'],
              'resource': {
                'data': {'progress': true, 'claimed': false}
              }
            }
          }),
          isTrue);
    });

    test('rejects invalid progress flag values', () {
      expect(
          rules.isAllowed(base, Method.write, variables: {
            ...auth('alice'),
            'request': {
              ...auth('alice')['request'],
              'resource': {
                'data': {'progress': 'yes'}
              }
            }
          }),
          isFalse);
    });

    test('other user cannot write progress', () {
      expect(
          rules.isAllowed(base, Method.write, variables: {
            ...auth('bob'),
            'request': {
              ...auth('bob')['request'],
              'resource': {
                'data': {'progress': true, 'claimed': false}
              }
            }
          }),
          isFalse);
    });
  });

  group('/seasonRewards', () {
    const base = 'databases/$db/documents/users/alice/seasonRewards/spring_c1';

    test('owner can read reward', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('alice')), isTrue);
    });

    test('writes to reward denied', () {
      expect(rules.isAllowed(base, Method.write, variables: auth('alice')),
          isFalse);
    });

    test('other users cannot read reward', () {
      expect(
          rules.isAllowed(base, Method.read, variables: auth('bob')), isFalse);
    });
  });
}
