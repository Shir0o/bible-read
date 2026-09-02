import 'dart:async';

import 'package:flutter/material.dart';

import '../services/reference_parser.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';
import 'common_styles.dart';
import 'group_plan_keys.dart';

/// Asks which chapter a plan should begin with.
///
/// [books] is the plan's book list in reading order. Resolves to the chosen
/// reference (e.g. `'Jeremiah 1'`), or null if the reader backed out.
Future<String?> showStartChapterSheet(
  BuildContext context, {
  required List<String> books,
  required String currentRef,
  VibrationService vibrationService = const VibrationService(),
}) {
  if (books.isEmpty) return Future<String?>.value(null);
  return showAppSheet<String>(
    context: context,
    fullHeight: true,
    builder: (_) => _StartChapterSheet(
      books: books,
      currentRef: currentRef,
      vibrationService: vibrationService,
    ),
  );
}

class _StartChapterSheet extends StatefulWidget {
  final List<String> books;
  final String currentRef;
  final VibrationService vibrationService;

  const _StartChapterSheet({
    required this.books,
    required this.currentRef,
    required this.vibrationService,
  });

  @override
  State<_StartChapterSheet> createState() => _StartChapterSheetState();
}

class _StartChapterSheetState extends State<_StartChapterSheet> {
  late String _openBook;
  late String _draftBook;
  late int _draftChapter;

  @override
  void initState() {
    super.initState();
    final parsed = ReferenceParser.parseBook(widget.currentRef);
    final book = (parsed != null && widget.books.contains(parsed))
        ? parsed
        : widget.books.first;
    _openBook = book;
    _draftBook = book;
    _draftChapter = _chapterOf(widget.currentRef) ?? 1;
  }

  int? _chapterOf(String reference) {
    final match = RegExp(r'(\d+)\s*$').firstMatch(reference.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Position of a chapter across the whole plan, so "is this before the start"
  /// is comparable between different books.
  int _planIndex(String book, int chapter) {
    var total = 0;
    for (final b in widget.books) {
      if (b == book) return total + (chapter - 1);
      total += ReferenceParser.chapterCount(b) ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final openChapters = ReferenceParser.chapterCount(_openBook) ?? 0;
    final draftIndex = _planIndex(_draftBook, _draftChapter);
    final wholeBookIsBefore = _planIndex(_openBook, openChapters) < draftIndex;

    return Column(
      key: GroupPlanKeys.startSheet,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start at',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: AppTheme.fontSerif,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Pick the chapter day one begins with. Anything before '
                      'it is left out of the plan.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              IconButton(
                key: GroupPlanKeys.startSheetClose,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: colorScheme.surfaceContainer,
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rField),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.hPadding,
            ),
            itemCount: widget.books.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.gap8),
            itemBuilder: (context, i) {
              final book = widget.books[i];
              final selected = book == _openBook;
              return _Pill(
                key: GroupPlanKeys.startSheetBookPill(book),
                label: book,
                selected: selected,
                onTap: () => setState(() => _openBook = book),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Divider(height: 1, thickness: 1, color: appColors.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              Text(
                '${_openBook.toUpperCase()} · $openChapters CHAPTERS',
                style: AppTextStyles.eyebrow(context).copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: AppSpacing.gap12),
              // Dimming alone would read as "disabled" across a whole book, so
              // say why the cells look inactive — they are still tappable.
              if (wholeBookIsBefore) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: appColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.rField),
                  ),
                  child: Text(
                    'Every chapter of $_openBook falls before '
                    '$_draftBook $_draftChapter. Tap one to move the start '
                    'here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.gap12),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var c = 1; c <= openChapters; c++)
                    _ChapterCell(
                      key: GroupPlanKeys.startSheetChapter(c),
                      chapter: c,
                      selected: _openBook == _draftBook && c == _draftChapter,
                      before: _planIndex(_openBook, c) < draftIndex,
                      onTap: () {
                        unawaited(widget.vibrationService.lightImpact());
                        setState(() {
                          _draftBook = _openBook;
                          _draftChapter = c;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(top: BorderSide(color: appColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                draftIndex == 0
                    ? 'Nothing is left out — this is the very beginning.'
                    : '$draftIndex chapters before $_draftBook $_draftChapter '
                        'will not be scheduled.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.gap12),
              FilledButton(
                key: GroupPlanKeys.startSheetCta,
                onPressed: () {
                  unawaited(widget.vibrationService.mediumImpact());
                  Navigator.of(context).pop('$_draftBook $_draftChapter');
                },
                child: Text('Start at $_draftBook $_draftChapter'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rChip),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rChip),
          border: Border.all(
            color: selected ? colorScheme.primary : appColors.border,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color:
                selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ChapterCell extends StatelessWidget {
  final int chapter;
  final bool selected;
  final bool before;
  final VoidCallback onTap;

  const _ChapterCell({
    super.key,
    required this.chapter,
    required this.selected,
    required this.before,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final Color background;
    final Color foreground;
    if (selected) {
      background = colorScheme.primary;
      foreground = colorScheme.onPrimary;
    } else if (before) {
      background = colorScheme.surfaceContainer;
      foreground = colorScheme.outline;
    } else {
      background = colorScheme.surfaceContainerLowest;
      foreground = colorScheme.onSurface;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: 'Chapter $chapter',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rChip),
        child: Container(
          width: 53,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
            border: Border.all(
              color: selected ? colorScheme.primary : appColors.border,
            ),
          ),
          child: Text(
            '$chapter',
            style: theme.textTheme.titleSmall?.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
