/// Names of Firestore collections used for group features.
class GroupCollections {
  GroupCollections._();

  /// Top-level groups collection.
  static const String groups = 'groups';

  /// Sub-collection containing group members.
  static const String members = 'members';

  /// Sub-collection containing the reading schedule.
  static const String schedule = 'schedule';

  /// Sub-collection containing join requests awaiting approval.
  static const String joinRequests = 'joinRequests';

  /// Sub-collection containing invitations to join.
  static const String invites = 'invites';
}
