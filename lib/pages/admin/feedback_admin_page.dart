import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/admin_role_service.dart';
import '../../theme/app_theme.dart';
import '../../services/error_logger.dart';
import '../../services/feedback_service.dart';
import '../../widgets/sub_header.dart';

enum _FeedbackStatusFilter {
  all,
  open,
  triaged,
  inProgress,
  resolved,
  notApplicable,
}

extension on _FeedbackStatusFilter {
  String get label {
    switch (this) {
      case _FeedbackStatusFilter.all:
        return 'All statuses';
      case _FeedbackStatusFilter.open:
        return 'Open';
      case _FeedbackStatusFilter.triaged:
        return 'Triaged';
      case _FeedbackStatusFilter.inProgress:
        return 'In Progress';
      case _FeedbackStatusFilter.resolved:
        return 'Resolved';
      case _FeedbackStatusFilter.notApplicable:
        return 'Not Applicable';
    }
  }

  String? get value {
    switch (this) {
      case _FeedbackStatusFilter.all:
        return null;
      case _FeedbackStatusFilter.open:
        return 'open';
      case _FeedbackStatusFilter.triaged:
        return 'triaged';
      case _FeedbackStatusFilter.inProgress:
        return 'inProgress';
      case _FeedbackStatusFilter.resolved:
        return 'resolved';
      case _FeedbackStatusFilter.notApplicable:
        return 'notApplicable';
    }
  }
}

/// Admin page displaying the bug report and feature request inboxes.
class FeedbackAdminPage extends StatefulWidget {
  FeedbackAdminPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AdminRoleService? adminRoleService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        adminRoleService = adminRoleService ??
            AdminRoleService(
              firestore: firestore ?? FirebaseFirestore.instance,
              auth: auth ?? FirebaseAuth.instance,
            );

  /// Firestore instance supplying feedback data.
  final FirebaseFirestore firestore;

  /// Service resolving whether the current user has admin access.
  final AdminRoleService adminRoleService;

  @override
  State<FeedbackAdminPage> createState() => _FeedbackAdminPageState();
}

class _FeedbackAdminPageState extends State<FeedbackAdminPage> {
  late final Future<bool> _isAdminFuture;
  late final Map<String, _FeedbackStatusFilter> _statusFilters;
  final Map<String, Map<String, dynamic>> _optimisticOverrides = {};

  @override
  void initState() {
    super.initState();
    _isAdminFuture = widget.adminRoleService.isAdmin(allowStale: false);
    _statusFilters = {
      FeedbackCollections.bugReports: _FeedbackStatusFilter.open,
      FeedbackCollections.featureRequests: _FeedbackStatusFilter.open,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        final hasAccess = snapshot.data ?? false;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                SubHeader(
                  title: 'Feedback Inbox',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                if (waiting)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!hasAccess)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'You do not have permission to view this page.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Bug Reports'),
                              Tab(text: 'Feature Requests'),
                            ],
                            labelStyle: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            indicatorSize: TabBarIndicatorSize.label,
                            indicatorWeight: 2.5,
                            labelPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildCollectionTab(
                                  FeedbackCollections.bugReports,
                                ),
                                _buildCollectionTab(
                                  FeedbackCollections.featureRequests,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionTab(String collection) {
    final filter = _statusFilters[collection] ?? _FeedbackStatusFilter.open;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _StatusSelect(
            selectKey: ValueKey('statusFilter_$collection'),
            options: _FeedbackStatusFilter.values
                .map((status) => status.label)
                .toList(),
            value: filter.label,
            onChanged: (label) {
              setState(() {
                _statusFilters[collection] = _FeedbackStatusFilter.values
                    .firstWhere((status) => status.label == label);
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.firestore
                .collection(collection)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                final stackTrace = snapshot.stackTrace;

                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'You do not have permission to view this feedback.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (error != null) {
                  ErrorLogger.log(error, stackTrace);
                }

                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Failed to load feedback entries. Please try again later.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;
              final filteredDocs = docs.where((doc) {
                final data = _mergedData(doc);
                return _matchesFilter(collection, data);
              }).toList();

              if (filteredDocs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No feedback matches the selected filter.'),
                  ),
                );
              }

              return ListView.builder(
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final data = _mergedData(doc);
                  return _FeedbackEntryCard(
                    key: ValueKey('feedbackCard_${doc.id}'),
                    data: data,
                    document: doc,
                    onResolve: () => _markResolved(doc, data),
                    onNotApplicable: () => _markNotApplicable(doc, data),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _mergedData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data());
    final override = _optimisticOverrides[doc.reference.path];
    if (override != null) {
      data.addAll(override);
    }
    return data;
  }

  bool _matchesFilter(String collection, Map<String, dynamic> data) {
    final filter = _statusFilters[collection] ?? _FeedbackStatusFilter.open;
    final target = filter.value;
    if (filter == _FeedbackStatusFilter.open) {
      final status = (data['status'] as String? ?? '').toLowerCase();
      return status != 'resolved' && status != 'notapplicable';
    }
    if (target == null) {
      return true;
    }
    final status = (data['status'] as String? ?? '').toLowerCase();
    return status == target.toLowerCase();
  }

  Future<void> _markResolved(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> currentData,
  ) async {
    final notes = await _promptForNotes(
      title: 'Add resolution notes',
      confirmLabel: 'Mark Resolved',
      initialValue: currentData['resolutionNotes'] as String?,
    );
    if (!mounted || notes == null) {
      return;
    }

    final now = Timestamp.now();
    final payload = <String, dynamic>{
      'status': 'resolved',
      'resolvedAt': now,
      'updatedAt': now,
      'resolutionNotes': notes.isEmpty ? null : notes,
    };
    await _applyUpdate(doc.reference, payload);
  }

  Future<void> _markNotApplicable(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> currentData,
  ) async {
    final notes = await _promptForNotes(
      title: 'Add resolution notes',
      confirmLabel: 'Mark Not Applicable',
      initialValue: currentData['resolutionNotes'] as String?,
    );
    if (!mounted || notes == null) {
      return;
    }

    final now = Timestamp.now();
    final payload = <String, dynamic>{
      'status': 'notApplicable',
      'resolvedAt': now,
      'updatedAt': now,
      'resolutionNotes': notes.isEmpty ? null : notes,
    };
    await _applyUpdate(doc.reference, payload);
  }

  Future<void> _applyUpdate(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> payload,
  ) async {
    final path = ref.path;
    final previous = _optimisticOverrides[path];
    setState(() {
      _optimisticOverrides[path] = {...?previous, ...payload};
    });

    try {
      await ref.update(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _optimisticOverrides.remove(path);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Feedback status updated.')));
    } catch (error, stackTrace) {
      ErrorLogger.log(error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        if (previous != null) {
          _optimisticOverrides[path] = previous;
        } else {
          _optimisticOverrides.remove(path);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update feedback. Please try again.'),
        ),
      );
    }
  }

  Future<String?> _promptForNotes({
    required String title,
    required String confirmLabel,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            key: const ValueKey('resolutionNotesField'),
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Resolution notes',
              hintText: 'Add any context about how this was resolved.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('submitResolutionNotes'),
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result;
  }
}

/// Status filter matching the design's `FeedbackInboxScreen` filter: a dim
/// "Status" label beside a bordered select button that expands a dropdown card
/// (selected option tinted with the primary colour).
class _StatusSelect extends StatefulWidget {
  const _StatusSelect({
    required this.options,
    required this.value,
    required this.onChanged,
    this.selectKey,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Key? selectKey;

  @override
  State<_StatusSelect> createState() => _StatusSelectState();
}

class _StatusSelectState extends State<_StatusSelect> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Status',
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: appColors.borderStrong, width: 1),
                ),
                child: InkWell(
                  key: widget.selectKey,
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _open = !_open);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.value,
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 17,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          Material(
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: appColors.border, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in widget.options)
                    InkWell(
                      onTap: () {
                        setState(() => _open = false);
                        widget.onChanged(option);
                      },
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: option == widget.value
                              ? appColors.primarySoft
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: option == widget.value
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FeedbackEntryCard extends StatelessWidget {
  const _FeedbackEntryCard({
    super.key,
    required this.data,
    required this.document,
    required this.onResolve,
    required this.onNotApplicable,
  });

  final Map<String, dynamic> data;
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final VoidCallback onResolve;
  final VoidCallback onNotApplicable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    final bodyStyle = theme.textTheme.bodyMedium;
    final rawStatus = (data['status'] as String? ?? 'unknown');
    final status = rawStatus.toLowerCase();
    final updatedAt = _formatTimestamp(data['updatedAt']);
    final resolvedAt = _formatTimestamp(data['resolvedAt']);
    final timestamp = _formatTimestamp(data['timestamp']);
    final notes = data['resolutionNotes'] as String?;
    final steps = data['reproductionSteps'] as String?;
    final email = data['email'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['title'] as String? ?? 'Untitled', style: titleStyle),
            const SizedBox(height: 8),
            if (timestamp != null)
              Text('Submitted: $timestamp', style: bodyStyle),
            if (updatedAt != null)
              Text('Updated: $updatedAt', style: bodyStyle),
            const SizedBox(height: 12),
            Text(
              data['description'] as String? ?? 'No description',
              style: bodyStyle,
            ),
            if (steps != null && steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Reproduction steps:', style: bodyStyle),
              const SizedBox(height: 4),
              Text(steps, style: bodyStyle),
            ],
            const SizedBox(height: 12),
            Text(
              'Status: $rawStatus',
              key: ValueKey('feedbackStatus_${document.id}'),
              style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (resolvedAt != null)
              Text('Resolved: $resolvedAt', style: bodyStyle),
            if (notes != null && notes.isNotEmpty)
              Text(
                'Resolution notes: $notes',
                key: ValueKey('resolutionNotes_${document.id}'),
                style: bodyStyle,
              ),
            if (notes == null || notes.isEmpty)
              const Text('Resolution notes: —'),
            const SizedBox(height: 12),
            Text(
              'Reporter: ${(data['displayName'] as String?) ?? 'Anonymous'}',
              style: bodyStyle,
            ),
            if (email != null && email.isNotEmpty)
              Text('Email: $email', style: bodyStyle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (status != 'resolved')
                  FilledButton(
                    key: ValueKey('resolveButton_${document.id}'),
                    onPressed: onResolve,
                    child: const Text('Mark Resolved'),
                  ),
                if (status != 'notapplicable')
                  FilledButton.tonal(
                    key: ValueKey('notApplicableButton_${document.id}'),
                    onPressed: onNotApplicable,
                    child: const Text('Mark Not Applicable'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _formatTimestamp(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toLocal().toString();
  }
  return null;
}
