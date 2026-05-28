import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service that resolves whether the current user has admin privileges.
class AdminRoleService {
  /// Creates an [AdminRoleService] using the provided Firebase instances.
  AdminRoleService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.cacheDuration = const Duration(minutes: 5),
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;

  /// Firebase authentication instance used to determine the current user.
  @protected
  final FirebaseAuth auth;

  /// Firestore instance used to read role metadata from the user profile.
  @protected
  final FirebaseFirestore firestore;

  /// Duration that determines how long cached admin values remain valid.
  final Duration cacheDuration;

  bool? _cachedAdminRole;
  DateTime? _cacheTimestamp;
  Future<bool>? _refreshing;
  Future<bool>? _lastRefresh;

  /// Returns the most recently cached admin value, if any.
  bool? get cachedAdminRole => _cachedAdminRole;

  @visibleForTesting
  bool get hasValidCache =>
      _cachedAdminRole != null &&
      _cacheTimestamp != null &&
      DateTime.now().difference(_cacheTimestamp!) < cacheDuration;

  @visibleForTesting
  Future<bool>? get refreshing => _refreshing ?? _lastRefresh;

  @visibleForTesting
  void primeCacheForTest(bool value, {DateTime? timestamp}) {
    _cachedAdminRole = value;
    _cacheTimestamp = timestamp ?? DateTime.now();
  }

  /// Returns `true` when the current user has an admin role either through a
  /// custom claim or their user document in Firestore.
  Future<bool> isAdmin({bool allowStale = true}) {
    if (hasValidCache) {
      return Future<bool>.value(_cachedAdminRole!);
    }

    if (_cachedAdminRole != null && allowStale) {
      unawaited(_refreshCache());
      return Future<bool>.value(_cachedAdminRole!);
    }

    return _refreshCache();
  }

  /// Fetches and caches the admin role eagerly.
  Future<bool> prewarm() {
    return _refreshCache();
  }

  Future<bool> _refreshCache() {
    _refreshing ??= fetchAdminRole()
        .then((value) {
          _cachedAdminRole = value;
          _cacheTimestamp = DateTime.now();
          return value;
        })
        .catchError((_) {
          _cacheTimestamp = DateTime.now();
          _cachedAdminRole ??= false;
          return _cachedAdminRole!;
        })
        .whenComplete(() {
          _refreshing = null;
        });
    _lastRefresh = _refreshing;

    return _refreshing!;
  }

  @protected
  Future<bool> fetchAdminRole() async {
    final user = auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? const <String, dynamic>{};
      if (_claimIsTrue(claims['admin']) || _claimIsTrue(claims['isAdmin'])) {
        return true;
      }
    } catch (_) {
      // Swallow errors from token refresh; fall back to Firestore check.
    }

    try {
      final userSnap = await firestore.collection('users').doc(user.uid).get();
      final data = userSnap.data();
      if (data == null) {
        return false;
      }

      if (_claimIsTrue(data['admin']) || _claimIsTrue(data['isAdmin'])) {
        return true;
      }

      final role = data['role'];
      if (role is String && (role == 'admin' || role == 'owner')) {
        return true;
      }

      final roles = data['roles'];
      if (roles is Map<String, dynamic>) {
        if (_claimIsTrue(roles['admin']) || _claimIsTrue(roles['isAdmin'])) {
          return true;
        }
      }
    } catch (_) {
      // Ignore errors from Firestore reads; treat as non-admin.
    }

    return false;
  }

  bool _claimIsTrue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }
}
