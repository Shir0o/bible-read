import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rulesText = File('firestore.rules').readAsStringSync();

  group('firestore.rules', () {
    test('includes friend request collections', () {
      expect(rulesText.contains('friendRequestsSent'), isTrue);
      expect(rulesText.contains('friendRequestsReceived'), isTrue);
      expect(rulesText.contains('nudges'), isTrue);
      expect(rulesText.contains('notificationPrefs'), isTrue);
      expect(rulesText.contains('notifications'), isTrue);
      expect(rulesText.contains('achievements'), isTrue);
    });

    test('friend request rules restrict fields', () {
      expect(rulesText.contains('friendRequestsSent/{toUid} {'), isTrue);
      expect(rulesText.contains("hasOnly(['timestamp'])"), isTrue);
      expect(rulesText.contains("hasOnly(['timestamp', 'name'])"), isTrue);
    });

    test('does not include deprecated readLog collection', () {
      expect(rulesText.contains('/readLog'), isFalse);
    });

    test('includes group rules with members and schedule', () {
      expect(rulesText.contains('match /groups/{groupId}'), isTrue);
      expect(rulesText.contains('match /members/{uid}'), isTrue);
      expect(rulesText.contains('match /schedule/{date}'), isTrue);
      expect(
          rulesText.contains('allow read: if request.auth != null;'), isTrue);
      expect(rulesText.contains('allow write: if isOwnerOrAdmin();'), isTrue);
    });

    test('guards manual plan metadata on groups', () {
      expect(rulesText.contains('manualPlanMetadataValid()'), isTrue);
      expect(rulesText.contains("manualPlanMapValid('manualPlanProgress')"),
          isTrue);
    });

    test('includes seasonal challenge rules', () {
      expect(rulesText.contains('match /seasons/{seasonId}'), isTrue);
      expect(rulesText.contains('match /challenges/{challengeId}'), isTrue);
      expect(rulesText.contains('match /seasonChallenges/{docId}'), isTrue);
      expect(rulesText.contains('match /seasonRewards/{docId}'), isTrue);
      expect(
          rulesText.contains('request.resource.data.progress == true'), isTrue);
      expect(
          rulesText.contains('request.resource.data.claimed == false'), isTrue);
    });
  });
}
