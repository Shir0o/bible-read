import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole files exempt from the scan.
const _allowlistedFiles = <String>{
  // Illustration artwork: hand-tuned palettes, not UI chrome.
  'lib/pages/check_in_page.dart',
  'lib/widgets/read_through_celebration.dart',
};

const _lineExemptMarker = '// token-exempt:';

final _rules = <String, RegExp>{
  'hex Color literal: use AppColors / ColorScheme': RegExp(r'Color\(0x'),
  'literal radius: use AppSpacing.r*': RegExp(
    r'(?:BorderRadius|Radius)\.circular\(\s*\d',
  ),
  'heavy FontWeight: use w700 or lighter': RegExp(
    r'FontWeight\.(?:bold|w800|w900)\b',
  ),
  'raw AppBar: use SubHeader on pushed pages': RegExp(r'\bAppBar\('),
  'buildAppBar was removed: use SubHeader': RegExp(r'\bbuildAppBar\('),
  // Content loading uses SkeletonLoader. A spinner is only for a submitting
  // button (or another reasoned exemption), always with the marker.
  'spinner: use SkeletonLoader, or mark a submitting button':
      RegExp(r'\bCircularProgressIndicator(?:\.adaptive)?\('),
  'ElevatedButton: use FilledButton (or Outlined/Text)':
      RegExp(r'\bElevatedButton\b'),
  'OutlineInputBorder: inputs take the theme\'s filled style':
      RegExp(r'\bOutlineInputBorder\('),
  // Variants live in the theme or AppButtonStyles (common_styles.dart).
  'styleFrom: use the theme or AppButtonStyles': RegExp(r'\bstyleFrom\('),
};

void main() {
  test('lib/ uses design tokens instead of raw literals', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/theme/') ||
          path == 'lib/firebase_options.dart' ||
          path == 'lib/widgets/sub_header.dart' ||
          path == 'lib/widgets/common_styles.dart' ||
          _allowlistedFiles.any(path.startsWith)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // dart format moves a trailing comment after an open paren onto the
        // next line, so the marker may sit on the following line too.
        if (line.contains(_lineExemptMarker) ||
            (i + 1 < lines.length &&
                lines[i + 1].trim().startsWith(_lineExemptMarker))) {
          continue;
        }
        for (final entry in _rules.entries) {
          final match = entry.value.firstMatch(line);
          if (match != null) {
            violations.add(
              '$path:${i + 1}: ${line.trim()}  [${entry.key}]',
            );
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Use a design token, or add a trailing '
          '"$_lineExemptMarker <reason>" comment for a deliberate literal:\n'
          '${violations.join('\n')}',
    );
  });
}
