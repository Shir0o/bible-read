import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockCacheManager extends Mock implements BaseCacheManager {}
