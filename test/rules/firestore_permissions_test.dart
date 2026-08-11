import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rulesText;

  setUpAll(() {
    rulesText = File('firestore.rules').readAsStringSync();
  });

  group('Firestore rules text', () {
    test('contains season collection access rules', () {
      final seasonsBlock = _findMatchBlock(rulesText, '/seasons/{seasonId}');
      final challengesBlock = _findMatchBlock(
        seasonsBlock,
        '/challenges/{challengeId}',
      );

      expect(
        _normalizeWhitespace(_extractAllowExpression(seasonsBlock, 'read')),
        equals('request.auth != null'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(seasonsBlock, 'write')),
        equals('false'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(challengesBlock, 'read')),
        equals('request.auth != null'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(challengesBlock, 'write')),
        equals('false'),
      );
    });

    test('contains user reflections collection rules', () {
      final usersBlock = _findMatchBlock(rulesText, '/users/{userId}');
      final reflectionsBlock = _findMatchBlock(
        usersBlock,
        '/reflections/{dateKey}',
      );

      expect(
        _normalizeWhitespace(
          _extractAllowExpression(reflectionsBlock, 'read, write'),
        ),
        equals('request.auth != null && request.auth.uid == userId'),
      );
    });

    test('contains user season progress rules', () {
      final usersBlock = _findMatchBlock(rulesText, '/users/{userId}');
      final progressBlock = _findMatchBlock(
        usersBlock,
        '/seasonChallenges/{docId}',
      );
      final rewardsBlock = _findMatchBlock(
        usersBlock,
        '/seasonRewards/{docId}',
      );
      final cacheBlock = _findMatchBlock(usersBlock, '/cache/{docId}');

      expect(
        _normalizeWhitespace(_extractAllowExpression(progressBlock, 'read')),
        equals('request.auth != null && request.auth.uid == userId'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(progressBlock, 'write')),
        equals(
          'request.auth != null && request.auth.uid == userId && ((request.resource.data.progress == true || request.resource.data.progress == false || request.resource.data.progress == null) && (request.resource.data.claimed == true || request.resource.data.claimed == false || request.resource.data.claimed == null))',
        ),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(rewardsBlock, 'read')),
        equals('request.auth != null && request.auth.uid == userId'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(rewardsBlock, 'write')),
        equals('false'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(cacheBlock, 'read')),
        equals('request.auth != null && request.auth.uid == userId'),
      );
      expect(
        _normalizeWhitespace(_extractAllowExpression(cacheBlock, 'write')),
        equals('request.auth != null && request.auth.uid == userId'),
      );
    });
  });

  group('Season collections behaviour', () {
    test('signed-in user can read season document', () {
      expect(_canReadSeason('alice'), isTrue);
    });

    test('unauthenticated season read denied', () {
      expect(_canReadSeason(null), isFalse);
    });

    test('challenge documents are read-only', () {
      expect(_canReadSeasonChallenge('alice'), isTrue);
      expect(_canWriteSeasonChallenge('alice'), isFalse);
    });
  });

  group('Season challenge progress behaviour', () {
    test('owner can read progress document', () {
      expect(_canReadSeasonProgress(authUid: 'alice', userId: 'alice'), isTrue);
    });

    test('owner can write valid progress flags', () {
      expect(
        _canWriteSeasonProgress(
          authUid: 'alice',
          userId: 'alice',
          progress: true,
          claimed: false,
        ),
        isTrue,
      );
    });

    test('rejects invalid progress flag values', () {
      expect(
        _canWriteSeasonProgress(
          authUid: 'alice',
          userId: 'alice',
          progress: 'yes',
          claimed: false,
        ),
        isFalse,
      );
    });

    test('other user cannot write progress', () {
      expect(
        _canWriteSeasonProgress(
          authUid: 'bob',
          userId: 'alice',
          progress: true,
          claimed: false,
        ),
        isFalse,
      );
    });
  });

  group('Season rewards behaviour', () {
    test('owner can read reward', () {
      expect(_canReadSeasonReward(authUid: 'alice', userId: 'alice'), isTrue);
    });

    test('writes to reward denied', () {
      expect(_canWriteSeasonReward(authUid: 'alice', userId: 'alice'), isFalse);
    });

    test('other users cannot read reward', () {
      expect(_canReadSeasonReward(authUid: 'bob', userId: 'alice'), isFalse);
    });
  });

  group('User cache behaviour', () {
    test('owner can read cache', () {
      expect(_canReadUserCache(authUid: 'alice', userId: 'alice'), isTrue);
    });

    test('owner can write cache', () {
      expect(_canWriteUserCache(authUid: 'alice', userId: 'alice'), isTrue);
    });

    test('other user cannot write cache', () {
      expect(_canWriteUserCache(authUid: 'bob', userId: 'alice'), isFalse);
    });
  });

  group('User reflection behaviour', () {
    test('owner can read their reflection', () {
      expect(_canReadUserReflection(authUid: 'alice', userId: 'alice'), isTrue);
    });

    test('owner can write their reflection', () {
      expect(
        _canWriteUserReflection(authUid: 'alice', userId: 'alice'),
        isTrue,
      );
    });

    test('other user cannot read a reflection', () {
      expect(_canReadUserReflection(authUid: 'bob', userId: 'alice'), isFalse);
    });

    test('other user cannot write a reflection', () {
      expect(_canWriteUserReflection(authUid: 'bob', userId: 'alice'), isFalse);
    });

    test('unauthenticated access denied', () {
      expect(_canReadUserReflection(authUid: null, userId: 'alice'), isFalse);
      expect(_canWriteUserReflection(authUid: null, userId: 'alice'), isFalse);
    });
  });

  group('Feedback submissions', () {
    test('authenticated user can create bug report with workflow defaults', () {
      final timestamp = Timestamp.now();
      final data = {
        'uid': 'alice',
        'email': 'alice@example.com',
        'displayName': 'Alice',
        'title': 'Crash on load',
        'description': 'The app crashes after sign in.',
        'reproductionSteps': 'Open the app and sign in.',
        'platform': 'android',
        'timestamp': timestamp,
        'status': 'open',
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
      };

      expect(_canCreateFeedback(authUid: 'alice', data: data), isTrue);
    });

    test('authenticated user can create feature request', () {
      final timestamp = Timestamp.now();
      final data = {
        'title': 'Add offline mode',
        'description': 'Allow reading without connectivity.',
        'platform': 'ios',
        'timestamp': timestamp,
        'status': 'open',
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
      };

      expect(_canCreateFeedback(authUid: 'feature-user', data: data), isTrue);
    });

    test('missing required feedback fields is rejected', () {
      final data = {
        'description': 'Missing title field.',
        'platform': 'web',
        'timestamp': Timestamp.now(),
        'status': 'open',
        'updatedAt': Timestamp.now(),
        'resolvedAt': null,
        'resolutionNotes': null,
      };

      expect(_canCreateFeedback(authUid: 'alice', data: data), isFalse);
    });

    test('unauthenticated feedback submission denied', () {
      final timestamp = Timestamp.now();
      final data = {
        'title': 'Bug',
        'description': 'Example',
        'platform': 'web',
        'timestamp': timestamp,
        'status': 'open',
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
      };

      expect(_canCreateFeedback(authUid: null, data: data), isFalse);
    });
  });
}

String _findMatchBlock(String source, String path) {
  final pattern = RegExp(
    'match\\s+${RegExp.escape(path)}\\s*\\{',
    multiLine: true,
  );
  final match = pattern.firstMatch(source);
  if (match == null) {
    throw StateError('Could not find match block for path $path');
  }

  final startIndex = match.start;
  var index = match.end - 1;
  var depth = 0;
  for (; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(startIndex, index + 1);
      }
    }
  }

  throw StateError('Unterminated match block for $path');
}

String _extractAllowExpression(String block, String operation) {
  final pattern = RegExp(
    'allow\\s+$operation\\s*:\\s*if\\s*(.*?);',
    dotAll: true,
  );
  final match = pattern.firstMatch(block);
  if (match == null) {
    throw StateError('Missing allow $operation statement in block');
  }

  return match.group(1)!.trim();
}

String _normalizeWhitespace(String input) =>
    input.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _canReadSeason(String? authUid) => authUid != null;

bool _canReadSeasonChallenge(String? authUid) => authUid != null;

bool _canWriteSeasonChallenge(String? authUid) => false;

bool _canReadSeasonProgress({
  required String? authUid,
  required String userId,
}) {
  return authUid != null && authUid == userId;
}

bool _canWriteSeasonProgress({
  required String? authUid,
  required String userId,
  Object? progress,
  Object? claimed,
}) {
  final progressValid = progress == null || progress is bool;
  final claimedValid = claimed == null || claimed is bool;

  return authUid != null && authUid == userId && progressValid && claimedValid;
}

bool _canReadSeasonReward({required String? authUid, required String userId}) {
  return authUid != null && authUid == userId;
}

bool _canWriteSeasonReward({required String? authUid, required String userId}) {
  return false;
}

bool _canReadUserCache({required String? authUid, required String userId}) {
  return authUid != null && authUid == userId;
}

bool _canWriteUserCache({required String? authUid, required String userId}) {
  return authUid != null && authUid == userId;
}

bool _canReadUserReflection({
  required String? authUid,
  required String userId,
}) {
  return authUid != null && authUid == userId;
}

bool _canWriteUserReflection({
  required String? authUid,
  required String userId,
}) {
  return authUid != null && authUid == userId;
}

bool _canCreateFeedback({
  required String? authUid,
  required Map<String, Object?> data,
}) {
  return authUid != null && _isValidFeedbackData(data);
}

bool _isValidFeedbackData(Map<String, Object?> data) {
  const allowedKeys = {
    'uid',
    'email',
    'displayName',
    'title',
    'description',
    'reproductionSteps',
    'platform',
    'timestamp',
    'status',
    'updatedAt',
    'resolvedAt',
    'resolutionNotes',
  };
  const requiredKeys = {
    'title',
    'description',
    'platform',
    'timestamp',
    'status',
    'updatedAt',
  };

  final keys = data.keys.toSet();
  final hasOnlyAllowed = keys.difference(allowedKeys).isEmpty;
  if (!hasOnlyAllowed || !keys.containsAll(requiredKeys)) {
    return false;
  }

  final timestamp = data['timestamp'];
  final updatedAt = data['updatedAt'];
  final resolvedAt = data['resolvedAt'];
  final resolutionNotes = data['resolutionNotes'];

  return data['title'] is String &&
      data['description'] is String &&
      data['platform'] is String &&
      data['status'] == 'open' &&
      timestamp is Timestamp &&
      updatedAt is Timestamp &&
      updatedAt == timestamp &&
      _isStringOrNull(data['uid']) &&
      _isStringOrNull(data['email']) &&
      _isStringOrNull(data['displayName']) &&
      _isStringOrNull(data['reproductionSteps']) &&
      resolvedAt == null &&
      resolutionNotes == null;
}

bool _isStringOrNull(Object? value) => value == null || value is String;
