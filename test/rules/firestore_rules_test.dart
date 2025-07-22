import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rulesText = File('firestore.rules').readAsStringSync();

  group('firestore.rules', () {
    test('includes friend request collections', () {
      expect(rulesText.contains('friendRequestsSent'), isTrue);
      expect(rulesText.contains('friendRequestsReceived'), isTrue);
      expect(rulesText.contains('nudges'), isTrue);
    });

    test('friend request rules restrict fields', () {
      expect(rulesText.contains("friendRequestsSent/{toUid} {"), isTrue);
      expect(rulesText.contains("hasOnly(['timestamp'])"), isTrue);
      expect(rulesText.contains("hasOnly(['timestamp', 'name'])"), isTrue);
    });

    test('does not include deprecated readLog collection', () {
      expect(rulesText.contains('/readLog'), isFalse);
    });
  });
}
