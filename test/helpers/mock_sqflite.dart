import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupSqfliteMock() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channels = [
    MethodChannel('com.tekartik.sqflite'),
    MethodChannel('sqflite'),
  ];

  for (final channel in channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getDatabasesPath') {
            return '.';
          }
          if (methodCall.method == 'openDatabase') {
            return 1;
          }
          if (methodCall.method == 'query') {
            return [];
          }
          if (methodCall.method == 'insert') {
            return 1;
          }
          if (methodCall.method == 'update') {
            return 1;
          }
          if (methodCall.method == 'delete') {
            return 1;
          }
          return null;
        });
  }
}
