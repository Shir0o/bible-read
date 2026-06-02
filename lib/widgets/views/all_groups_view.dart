import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../services/group_service.dart';
import '../../services/vibration_service.dart';
import '../common_styles.dart';
import '../find_group_card.dart';
import '../../pages/group_detail_page.dart';

/// View that lists all groups (Browse/Find Groups).
class AllGroupsView extends StatefulWidget {
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const AllGroupsView({
    super.key,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<AllGroupsView> createState() => _AllGroupsViewState();
}

class _AllGroupsViewState extends State<AllGroupsView>
    with AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Future<void> _openGroup(Group group) async {
    unawaited(widget.vibrationService.lightImpact());
    // Navigate to GroupDetailPage where user can see details and join
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroupDetailPage(
          group: group,
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = widget.auth.currentUser;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      unawaited(widget.vibrationService.lightImpact());
                      Navigator.of(context).pop();
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Find Groups',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title(
                        context,
                      ).copyWith(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: () {
                      unawaited(widget.vibrationService.lightImpact());
                      // Placeholder for filter options
                    },
                  ),
                ],
              ),
            ),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search groups',
                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            // Content
            Expanded(
              child: StreamBuilder<List<Group>>(
                stream: widget.groupService.allGroups(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allGroups = snapshot.data!;

                  // Filter logic:
                  // 1. Must be public or user explicitly searches for it (not implemented here, assuming generic search).
                  // 2. Name contains query.
                  final filtered = allGroups.where((g) {
                    final nameMatch = g.name.toLowerCase().contains(
                          _searchQuery,
                        );
                    return g.isPublic && nameMatch;
                  }).toList();

                  if (user == null) {
                    return _buildGroupList(filtered);
                  }

                  // We filter out groups the user has already joined to keep the list clean for "Finding"
                  return StreamBuilder<List<Group>>(
                    stream: widget.groupService.groupsForUser(user.uid),
                    builder: (context, myGroupsSnap) {
                      final myGroups = myGroupsSnap.data ?? [];
                      final myGroupIds = myGroups.map((g) => g.id).toSet();

                      final availableGroups = filtered
                          .where((g) => !myGroupIds.contains(g.id))
                          .toList();

                      if (availableGroups.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return _buildGroupList(availableGroups);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupList(List<Group> groups) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Text(
            'RECOMMENDED FOR YOU',
            style: AppTextStyles.subtitle(context).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...groups.map(
          (group) => FindGroupCard(
            group: group,
            groupService: widget.groupService,
            onJoin: () => _openGroup(group),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No groups found',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or come back later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
