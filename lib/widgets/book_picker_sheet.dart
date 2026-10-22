import 'dart:async';

import 'package:flutter/material.dart';

import '../services/reference_parser.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';

/// Widget keys for the book picker, so tests find controls by identity.
abstract final class BookPickerKeys {
  static const sheet = Key('book_picker_sheet');
  static const search = Key('book_picker_search');
  static const clear = Key('book_picker_clear');
  static const close = Key('book_picker_close');
  static const done = Key('book_picker_done');

  static Key tile(String book) => Key('book_picker_tile_$book');
  static Key quickSet(String name) => Key('book_picker_set_$name');
  static Key sectionToggle(String name) => Key('book_picker_section_$name');
}

/// Asks which books a plan reads.
///
/// Resolves to the picked books in Bible order, or null if the reader backed
/// out.
Future<List<String>?> showBookPickerSheet(
  BuildContext context, {
  required Iterable<String> selected,
  VibrationService vibrationService = const VibrationService(),
}) {
  return showAppSheet<List<String>>(
    context: context,
    fullHeight: true,
    builder: (_) => _BookPickerSheet(
      initial: selected.toSet(),
      vibrationService: vibrationService,
    ),
  );
}

/// Books from [first] to [last] inclusive, in Bible order.
List<String> _range(String first, String last) {
  final books = ReferenceParser.allBooks;
  return books.sublist(books.indexOf(first), books.indexOf(last) + 1);
}

final _sections = <(String, List<String>)>[
  ('The Law', _range('Genesis', 'Deuteronomy')),
  ('History', _range('Joshua', 'Esther')),
  ('Poetry', _range('Job', 'Song of Songs')),
  ('Prophets', _range('Isaiah', 'Malachi')),
  ('Gospels and Acts', _range('Matthew', 'Acts')),
  ("Paul's letters", _range('Romans', 'Philemon')),
  ('Other letters and Revelation', _range('Hebrews', 'Revelation')),
];

final _quickSets = <(String, List<String>)>[
  ('Old Testament', _range('Genesis', 'Malachi')),
  ('New Testament', _range('Matthew', 'Revelation')),
  ('Gospels', _range('Matthew', 'John')),
  ("Paul's letters", _range('Romans', 'Philemon')),
];

class _BookPickerSheet extends StatefulWidget {
  final Set<String> initial;
  final VibrationService vibrationService;

  const _BookPickerSheet({
    required this.initial,
    required this.vibrationService,
  });

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  bool _hasAll(List<String> books) => books.every(_selected.contains);

  /// Adds every book of [books], or removes them all when all are picked.
  void _toggleAll(List<String> books) {
    unawaited(widget.vibrationService.lightImpact());
    setState(() {
      if (_hasAll(books)) {
        _selected.removeAll(books);
      } else {
        _selected.addAll(books);
      }
    });
  }

  void _toggle(String book) {
    unawaited(widget.vibrationService.lightImpact());
    setState(() {
      if (!_selected.remove(book)) _selected.add(book);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final query = _query.trim().toLowerCase();
    final picked = ReferenceParser.allBooks.where(_selected.contains).toList();
    final chapters = picked.fold<int>(
      0,
      (total, book) => total + (ReferenceParser.chapterCount(book) ?? 0),
    );

    return Column(
      key: BookPickerKeys.sheet,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gap20, AppSpacing.gap16,
              AppSpacing.gap20, AppSpacing.gap12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Choose books',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              TextButton(
                key: BookPickerKeys.clear,
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        unawaited(widget.vibrationService.lightImpact());
                        setState(_selected.clear);
                      },
                child: const Text('Clear'),
              ),
              const SizedBox(width: AppSpacing.gap4),
              IconButton(
                key: BookPickerKeys.close,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
                style: IconButton.styleFrom(
                  // token-exempt: tonal 44px icon tile; no themed equivalent
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
          child: TextField(
            key: BookPickerKeys.search,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Find a book',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.gap12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.hPadding,
            ),
            itemCount: _quickSets.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.gap8),
            itemBuilder: (context, i) {
              final (name, books) = _quickSets[i];
              final on = _hasAll(books);
              return Semantics(
                button: true,
                selected: on,
                child: InkWell(
                  key: BookPickerKeys.quickSet(name),
                  onTap: () => _toggleAll(books),
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gap16,
                    ),
                    decoration: BoxDecoration(
                      color: on
                          ? appColors.primarySoft
                          : colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      border: Border.all(
                        color: on ? colorScheme.primary : appColors.border,
                      ),
                    ),
                    child: Text(
                      name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: on
                            ? appColors.primaryPress
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.gap12),
        Divider(height: 1, thickness: 1, color: appColors.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding,
                AppSpacing.gap8, AppSpacing.hPadding, AppSpacing.gap20),
            children: [
              for (final (name, books) in _sections)
                if (books.any((b) => b.toLowerCase().contains(query)))
                  _buildSection(
                    context,
                    name,
                    books,
                    books.where((b) => b.toLowerCase().contains(query)),
                  ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(top: BorderSide(color: appColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gap20, AppSpacing.gap12,
              AppSpacing.gap20, AppSpacing.gap12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${picked.length} '
                      '${picked.length == 1 ? 'book' : 'books'} · '
                      '$chapters ${chapters == 1 ? 'chapter' : 'chapters'}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.gap2),
                    Text(
                      'Read in Bible order',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              FilledButton(
                key: BookPickerKeys.done,
                onPressed: picked.isEmpty
                    ? null
                    : () {
                        unawaited(widget.vibrationService.mediumImpact());
                        Navigator.of(context).pop(picked);
                      },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A titled group of book tiles with an "Add all" / "Remove all" action.
  /// [shown] narrows the tiles to the search; the action covers the section.
  Widget _buildSection(
    BuildContext context,
    String name,
    List<String> books,
    Iterable<String> shown,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.gap12),
          child: Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
              TextButton(
                key: BookPickerKeys.sectionToggle(name),
                onPressed: () => _toggleAll(books),
                child: Text(_hasAll(books) ? 'Remove all' : 'Add all'),
              ),
            ],
          ),
        ),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpacing.gap8,
            crossAxisSpacing: AppSpacing.gap8,
            mainAxisExtent: 60,
          ),
          children: [
            for (final book in shown)
              _BookTile(
                key: BookPickerKeys.tile(book),
                book: book,
                selected: _selected.contains(book),
                onTap: () => _toggle(book),
              ),
          ],
        ),
      ],
    );
  }
}

class _BookTile extends StatelessWidget {
  final String book;
  final bool selected;
  final VoidCallback onTap;

  const _BookTile({
    super.key,
    required this.book,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final chapters = ReferenceParser.chapterCount(book) ?? 0;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rChip),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap8,
            vertical: AppSpacing.gap6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? appColors.primarySoft
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
            border: Border.all(
              color: selected ? colorScheme.primary : appColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Long names ("1 Thessalonians") shrink rather than clip.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  book,
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected
                        ? appColors.primaryPress
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.gap2),
              Text(
                chapters == 1 ? '1 chapter' : '$chapters chapters',
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
