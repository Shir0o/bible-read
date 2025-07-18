import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rulesText = File('firestore.rules').readAsStringSync();

  group('firestore.rules', () {
    test('includes friend request collections', () {
      expect(rulesText.contains('friendRequestsSent'), isTrue);
      expect(rulesText.contains('friendRequestsReceived'), isTrue);
    });
  });
}
