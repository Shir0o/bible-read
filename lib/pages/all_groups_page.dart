import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/views/all_groups_view.dart';

/// Page that lists all groups (Browse/Find Groups).
class AllGroupsPage extends StatelessWidget {
  /// Service used to load and manage groups.
  final GroupService groupService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [AllGroupsPage].
  AllGroupsPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    // The AllGroupsView handles the Scaffold and its own app bar / header.
    return AllGroupsView(
      groupService: groupService,
      auth: auth,
      vibrationService: vibrationService,
    );
  }
}
