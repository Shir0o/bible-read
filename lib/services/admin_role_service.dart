import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service that resolves whether the current user has admin privileges.
class AdminRoleService {
  /// Creates an [AdminRoleService] using the provided Firebase instances.
  AdminRoleService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  /// Firebase authentication instance used to determine the current user.
  @protected
  final FirebaseAuth auth;

  /// Firestore instance used to read role metadata from the user profile.
  @protected
  final FirebaseFirestore firestore;

  /// Returns `true` when the current user has an admin role either through a
  /// custom claim or their user document in Firestore.
  Future<bool> isAdmin() async {
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
