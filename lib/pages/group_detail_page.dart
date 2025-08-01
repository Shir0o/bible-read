import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/schedule_item_tile.dart';

/// Page showing the members and schedule for a group.
class GroupDetailPage extends StatefulWidget {
  /// Group being displayed.
  final Group group;

  /// Service used for group operations.
  final GroupService groupService;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Creates a [GroupDetailPage].
  GroupDetailPage({
    super.key,
    required this.group,
    GroupService? groupService,
    FirebaseAuth? auth,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  Future<void> _editSchedule([GroupSchedule? schedule]) async {
    final controller = TextEditingController(
      text: schedule?.chapters.join(', ') ?? '',
    );
    DateTime selected = schedule?.date ?? DateTime.now();

    final result = await showDialog<GroupSchedule>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(schedule == null ? 'Add Schedule' : 'Edit Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Chapters (comma separated)',
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selected,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      selected = picked;
                    });
                  }
                },
                child: Text(selected.toIso8601String().split('T').first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final chapters = controller.text
                    .split(',')
                    .map((c) => c.trim())
                    .where((c) => c.isNotEmpty)
                    .toList();
                Navigator.of(context).pop(
                  GroupSchedule(date: selected, chapters: chapters),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await widget.groupService
          .updateSchedule(groupId: widget.group.id, schedule: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final isOwner = user != null && user.uid == widget.group.ownerUid;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(widget.group.name),
      floatingActionButton:
          isOwner ? FloatingActionButton(onPressed: _editSchedule, child: const Icon(Icons.add)) : null,
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Members', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            StreamBuilder<List<String>>(
              stream: widget.groupService.memberNames(widget.group.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Failed to load members');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final names = snapshot.data!;
                if (names.isEmpty) {
                  return const Text('No members');
                }
                return Column(
                  children:
                      names.map((n) => ListTile(title: Text(n))).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Schedule', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            StreamBuilder<List<GroupSchedule>>(
              stream: widget.groupService.schedule(widget.group.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Failed to load schedule');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final schedule = snapshot.data!;
                if (schedule.isEmpty) {
                  return const Text('No schedule');
                }
                return Column(
                  children: schedule
                      .map(
                        (s) => ScheduleItemTile(
                          schedule: s,
                          onEdit: isOwner ? () => _editSchedule(s) : null,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
