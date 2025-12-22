import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/views/groups_view.dart';

/// Page that lists all groups.
class GroupsPage extends StatelessWidget {
  /// Service used to load and manage groups.
  final GroupService groupService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [GroupsPage].
  GroupsPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Groups',
        automaticallyImplyLeading: false,
      ),
      body: GroupsView(
        groupService: groupService,
        auth: auth,
        vibrationService: vibrationService,
      ),
    );
  }
}
