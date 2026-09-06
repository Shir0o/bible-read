import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/read_through.dart';
import '../../pages/read_throughs_page.dart';
import '../../services/read_through_service.dart';
import '../../theme/app_theme.dart';

/// How many times through, on the Journey tab, and the way in to the history.
class ReadThroughCard extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadThroughService? service;

  const ReadThroughCard({
    super.key,
    required this.firestore,
    required this.auth,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final resolved = service ?? ReadThroughService(firestore: firestore);

    return StreamBuilder<List<ReadThrough>>(
      stream: resolved.watch(user.uid),
      builder: (context, snapshot) {
        final counts = ReadThroughService.countsFrom(
          snapshot.data ?? const <ReadThrough>[],
        );
        return _Card(
          counts: counts,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReadThroughsPage(
                firestore: firestore,
                auth: auth,
                service: service,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final ReadThroughCounts counts;
  final VoidCallback onTap;

  const _Card({required this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.rCard),
            border: Border.all(color: appColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Times through', style: textTheme.titleLarge),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Count(
                        value: counts.wholeBible,
                        label: 'Whole Bible',
                        accented: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Count(
                        value: counts.oldTestament,
                        label: 'Old Testament',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Count(
                        value: counts.newTestament,
                        label: 'New Testament',
                      ),
                    ),
                  ],
                ),
              ),
              if (counts.wholeBible == 0 &&
                  counts.newTestament == 0 &&
                  counts.oldTestament == 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Finish a testament and it lands here.',
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int value;
  final String label;
  final bool accented;

  const _Count({
    required this.value,
    required this.label,
    this.accented = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color:
            accented ? appColors.accentSoft : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
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
            style: textTheme.headlineSmall?.copyWith(
              height: 1,
              color: accented
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: accented
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
