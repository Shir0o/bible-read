import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Firestore collection names used by [FeedbackService].
class FeedbackCollections {
  FeedbackCollections._();

  /// Collection storing submitted bug reports.
  static const String bugReports = 'bugReports';

  /// Collection storing submitted feature requests.
  static const String featureRequests = 'featureRequests';
}

/// Service responsible for submitting feedback to Firestore.
class FeedbackService {
  /// Firestore instance used for writing feedback documents.
  final FirebaseFirestore firestore;

  /// Firebase auth instance used for resolving the current user.
  final FirebaseAuth auth;

  /// Creates a [FeedbackService] using the default Firebase instances when none
  /// are provided.
  FeedbackService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  /// Submits a bug report with the provided [title], [description], and optional
  /// [reproductionSteps].
  Future<void> submitBugReport({
    required String title,
    required String description,
    String? reproductionSteps,
  }) async {
    await _submit(
      collection: FeedbackCollections.bugReports,
      title: title,
      description: description,
      reproductionSteps: reproductionSteps,
    );
  }

  /// Submits a feature request with the provided [title] and [description].
  Future<void> submitFeatureRequest({
    required String title,
    required String description,
    String? reproductionSteps,
  }) async {
    await _submit(
      collection: FeedbackCollections.featureRequests,
      title: title,
      description: description,
      reproductionSteps: reproductionSteps,
    );
  }

  Future<void> _submit({
    required String collection,
    required String title,
    required String description,
    String? reproductionSteps,
  }) async {
    final user = auth.currentUser;
    final now = Timestamp.now();
    final data = <String, Object?>{
      'uid': user?.uid,
      'email': user?.email,
      'displayName': user?.displayName,
      'title': title.trim(),
      'description': description.trim(),
      'platform': _currentPlatform(),
      'timestamp': now,
      'updatedAt': now,
      'status': 'open',
      'resolvedAt': null,
      'resolutionNotes': null,
    };
    final normalizedSteps = reproductionSteps?.trim();
    if (normalizedSteps != null && normalizedSteps.isNotEmpty) {
      data['reproductionSteps'] = normalizedSteps;
    }

    await firestore.collection(collection).add(data);
  }

  String _currentPlatform() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
