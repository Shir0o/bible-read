import 'package:flutter_test/flutter_test.dart';

import '../../tool/version_code.dart';

void main() {
  group('deriveVersionCode', () {
    test('maps plain release tags onto the ADR-0001 contract', () {
      // major * 10000 + minor * 100 + patch, worked out by hand.
      expect(deriveVersionCode('v1.26.0').versionCode, 12600);
      expect(deriveVersionCode('v2.3.4').versionCode, 20304);
      expect(deriveVersionCode('v0.1.0').versionCode, 100);
      expect(deriveVersionCode('v10.0.0').versionCode, 100000);
    });

    test('accepts tags without the v prefix', () {
      expect(deriveVersionCode('1.2.3').versionCode, 10203);
    });

    test('ignores a pre-release suffix when deriving the code', () {
      expect(deriveVersionCode('v1.2.3-rc.1').versionCode, 10203);
      expect(deriveVersionCode('v1.2.3-beta').versionCode, 10203);
      expect(deriveVersionCode('v1.2.3-rc.1+build.5').isValid, isFalse);
    });

    test('rejects a minor or patch that would collide under the formula', () {
      expect(deriveVersionCode('v1.100.0').isValid, isFalse);
      expect(deriveVersionCode('v1.2.100').isValid, isFalse);
    });

    test('rejects a code beyond the Android maximum', () {
      expect(deriveVersionCode('v210001.0.0').isValid, isFalse);
    });

    const hostileTags = <String>[
      '',
      'v',
      'v1',
      'v1.2',
      'v1.2.3.4',
      'v01.2.3',
      'v1.02.3',
      'v1.2.03',
      'v1.x.3',
      '1.2.3+4',
      'release-1.2.3',
      'v1.2.3; echo pwned',
      r'v1.2.3$(id)',
      'v1.2.3 | rm -rf /',
      'v1.2.3 && id',
      'v1.2.3\n1.2.4',
      ' v1.2.3',
      'v1.2.3 ',
      'v99999999999999999999999999.0.0',
    ];

    for (final tag in hostileTags) {
      test('rejects hostile or malformed tag: $tag', () {
        final result = deriveVersionCode(tag);
        expect(result.isValid, isFalse, reason: 'tag: $tag');
        expect(result.versionCode, isNull);
        expect(result.error, isNotNull);
      });
    }
  });
}
