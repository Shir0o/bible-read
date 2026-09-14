// Pure, strictly-validating Android `versionCode` derivation for release tags.
//
// ADR-0001 fixes the contract: versionCode = major * 10000 + minor * 100 + patch.
// This module is the single implementation of that contract. The release
// workflow calls it instead of re-deriving the arithmetic in a shell body, so a
// hostile tag is rejected as data before it can reach a shell.
//
// Usage: dart tool/version_code.dart <tag>
// Prints the derived versionCode on success; writes the reason to stderr and
// exits non-zero on failure.

import 'dart:io';

/// The largest versionCode the Android platform accepts.
const int maxAndroidVersionCode = 2100000000;

/// The outcome of deriving a versionCode from a release tag.
class VersionCodeResult {
  const VersionCodeResult.valid(int this.versionCode) : error = null;
  const VersionCodeResult.invalid(String this.error) : versionCode = null;

  /// The derived versionCode, or null when [isValid] is false.
  final int? versionCode;

  /// Why the tag was rejected, or null when [isValid] is true.
  final String? error;

  bool get isValid => versionCode != null;
}

/// v?MAJOR.MINOR.PATCH with an optional -prerelease suffix.
///
/// Leading zeros are rejected (semantic versioning forbids them), as are empty
/// segments, build metadata, and any character that is not a digit, a dot, or a
/// hyphen -- so shell metacharacters can never match.
final RegExp _releaseTagPattern = RegExp(
  r'^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$',
);

int? _parseComponent(String value) {
  try {
    return int.parse(value);
  } on FormatException {
    return null;
  }
}

/// Derives the Android versionCode for [tag], or reports why it is invalid.
VersionCodeResult deriveVersionCode(String tag) {
  final match = _releaseTagPattern.firstMatch(tag);
  if (match == null) {
    return const VersionCodeResult.invalid(
      'expected vMAJOR.MINOR.PATCH with an optional -prerelease suffix',
    );
  }

  final major = _parseComponent(match.group(1)!);
  final minor = _parseComponent(match.group(2)!);
  final patch = _parseComponent(match.group(3)!);
  if (major == null || minor == null || patch == null) {
    return const VersionCodeResult.invalid(
      'a numeric segment does not fit in an int',
    );
  }

  // The contract only stays collision-free, and within Android's limit, for
  // two-digit minor and patch components.
  if (minor > 99 || patch > 99) {
    return VersionCodeResult.invalid(
      'minor and patch must be below 100 (got $minor.$patch)',
    );
  }

  final versionCode = major * 10000 + minor * 100 + patch;
  if (versionCode > maxAndroidVersionCode) {
    return VersionCodeResult.invalid(
      'versionCode $versionCode exceeds the Android maximum of $maxAndroidVersionCode',
    );
  }

  return VersionCodeResult.valid(versionCode);
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/version_code.dart <tag>');
    exitCode = 64;
    return;
  }

  final tag = args.single;
  final result = deriveVersionCode(tag);
  if (!result.isValid) {
    stderr.writeln(
        '::error::Tag "$tag" is not a valid release tag: ${result.error}.');
    exitCode = 65;
    return;
  }

  stdout.writeln(result.versionCode);
}
