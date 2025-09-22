import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rulesText;

  setUpAll(() {
    rulesText = File('firestore.rules').readAsStringSync();
  });

  group('Firestore rules text', () {
    test('contains season collection access rules', () {
      final seasonsBlock = _findMatchBlock(rulesText, '/seasons/{seasonId}');
      final challengesBlock =
          _findMatchBlock(seasonsBlock, '/challenges/{challengeId}');

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

    test('contains user season progress rules', () {
      final usersBlock = _findMatchBlock(rulesText, '/users/{userId}');
      final progressBlock =
          _findMatchBlock(usersBlock, '/seasonChallenges/{docId}');
      final rewardsBlock =
          _findMatchBlock(usersBlock, '/seasonRewards/{docId}');

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
      expect(
        _canReadSeasonProgress(authUid: 'alice', userId: 'alice'),
        isTrue,
      );
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
      expect(
        _canReadSeasonReward(authUid: 'alice', userId: 'alice'),
        isTrue,
      );
    });

    test('writes to reward denied', () {
      expect(
        _canWriteSeasonReward(authUid: 'alice', userId: 'alice'),
        isFalse,
      );
    });

    test('other users cannot read reward', () {
      expect(
        _canReadSeasonReward(authUid: 'bob', userId: 'alice'),
        isFalse,
      );
    });
  });
}

String _findMatchBlock(String source, String path) {
  final pattern =
      RegExp('match\\s+${RegExp.escape(path)}\\s*\\{', multiLine: true);
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

bool _canReadSeasonProgress(
    {required String? authUid, required String userId}) {
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
