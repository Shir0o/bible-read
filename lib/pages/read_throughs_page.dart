import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/read_through.dart';
import '../services/read_through_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sub_header.dart';
import 'add_read_through_page.dart';

/// The user's whole history: how many times they have finished each scope, and
/// every individual time.
class ReadThroughsPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadThroughService? service;

  const ReadThroughsPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.service,
  });

  @override
  State<ReadThroughsPage> createState() => _ReadThroughsPageState();
}

class _ReadThroughsPageState extends State<ReadThroughsPage> {
  late final ReadThroughService _service;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? ReadThroughService(firestore: widget.firestore);
  }

  Future<void> _open({ReadThrough? existing}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddReadThroughPage(
          firestore: widget.firestore,
          auth: widget.auth,
          existing: existing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.auth.currentUser;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Read-Throughs',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: user == null
                  ? const SizedBox.shrink()
                  : StreamBuilder<List<ReadThrough>>(
                      stream: _service.watch(user.uid),
                      builder: (context, snapshot) {
                        final rows = snapshot.data ?? const <ReadThrough>[];
                        final counts = ReadThroughService.countsFrom(rows);
                        // Newest first: the most recent time through is the
                        // one a reader came here to see.
                        final ordered = rows.reversed.toList();

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                          children: [
                            _CountRow(counts: counts),
                            const SizedBox(height: 26),
                            if (ordered.isEmpty)
                              const _EmptyState()
                            else ...[
                              const _SectionRule('Every time through'),
                              const SizedBox(height: 12),
                              for (final row in ordered) ...[
                                _ReadThroughTile(
                                  readThrough: row,
                                  onTap: () => _open(existing: row),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                            const SizedBox(height: 8),
                            _AddRow(onTap: _open),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three counters. The whole Bible is marked as derived because it is not
/// tallied directly — it follows from the two testaments.
class _CountRow extends StatelessWidget {
  final ReadThroughCounts counts;

  const _CountRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight so the three tiles match the tallest, which a plain
    // stretch cannot do inside a scroll view's unbounded height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _CountTile(
              value: counts.wholeBible,
              label: 'Whole Bible',
              footnote: 'Derived',
              accented: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CountTile(
              value: counts.oldTestament,
              label: 'Old Testament',
              footnote: 'on lap ${counts.currentLap(
                ReadThroughScope.oldTestament,
              )}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CountTile(
              value: counts.newTestament,
              label: 'New Testament',
              footnote: 'on lap ${counts.currentLap(
                ReadThroughScope.newTestament,
              )}',
            ),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final int value;
  final String label;
  final String footnote;
  final bool accented;

  const _CountTile({
    required this.value,
    required this.label,
    required this.footnote,
    this.accented = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
      decoration: BoxDecoration(
        color: accented
            ? appColors.accentSoft
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: accented
              ? colorScheme.tertiary.withValues(alpha: 0.28)
              : appColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.displaySmall?.copyWith(
              height: 1,
              color: accented
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: accented
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            accented ? footnote.toUpperCase() : footnote,
            style: accented
                ? textTheme.labelSmall?.copyWith(color: colorScheme.tertiary)
                : textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReadThroughTile extends StatelessWidget {
  final ReadThrough readThrough;
  final VoidCallback onTap;

  const _ReadThroughTile({required this.readThrough, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    final isBible = readThrough.scope == ReadThroughScope.wholeBible;
    final isHandEntered = !readThrough.source.isAnnounceable && !isBible;

    return Semantics(
      button: true,
      label: '${readThrough.scope.label}, ${readThrough.ordinalLabel}, '
          '${readThrough.subtitle}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: isBible
                ? appColors.accentSoft
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.rCard),
            border: Border.all(
              color: isBible
                  ? colorScheme.tertiary.withValues(alpha: 0.28)
                  : appColors.border,
            ),
          ),
          child: Row(
            children: [
              _ScopeMark(scope: readThrough.scope),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${readThrough.scope.label} · '
                      '${readThrough.ordinalLabel}',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      readThrough.subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: isBible
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isHandEntered) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.rChip),
                  ),
                  child: Text(
                    'ADDED',
                    style: textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The gold sun mark for a whole Bible, a book for a testament.
class _ScopeMark extends StatelessWidget {
  final ReadThroughScope scope;

  const _ScopeMark({required this.scope});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    if (scope == ReadThroughScope.wholeBible) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF2A2438), width: 1.5),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE9A8), Color(0xFFFFC24D)],
          ),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 19,
          color: Color(0xFF2A2438),
        ),
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: appColors.primarySoft,
        border: Border.all(color: appColors.primaryLine),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        size: 18,
        color: colorScheme.primary,
      ),
    );
  }
}

class _SectionRule extends StatelessWidget {
  final String label;
  const _SectionRule(this.label);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final line = Expanded(
      child: Divider(color: colorScheme.outlineVariant, height: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        line,
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rButton),
      child: Container(
        height: AppSpacing.buttonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.rButton),
          border: Border.all(
            color: AppColors.of(context).borderStrong,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 19, color: colorScheme.primary),
            const SizedBox(width: 9),
            Text(
              'Add a past read-through',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(
            'No times through yet.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Finish a testament and it lands here. Read one before you used '
            'the app? Add it below.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
