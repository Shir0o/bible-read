// Security invariants for the GitHub Actions workflows.
//
// These assertions read the workflow definitions as data. They are the CI
// enforcement of the release-pipeline hardening in docs/adr/0001-release-automation.md:
// a regression here fails `flutter test`, not a release.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class Workflow {
  Workflow(this.file, this.text);

  final File file;
  final String text;

  String get name => file.uri.pathSegments.last;
  List<String> get lines => text.split('\n');
}

Directory repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'Could not find the repository root from ${Directory.current.path}');
    }
    dir = parent;
  }
}

List<Workflow> workflows() {
  final dir = Directory('${repoRoot().path}/.github/workflows');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => Workflow(f, f.readAsStringSync())).toList();
}

/// The text of every `run:` body in [workflow], paired with its first line
/// number, so an invariant can point at the offending shell body.
List<MapEntry<int, String>> runBodies(Workflow workflow) {
  final lines = workflow.lines;
  final runPattern = RegExp(r'^(\s*)run:\s*(.*)$');
  final inlineMarkers = {'|', '>', '|-', '>-', '|+', '>+'};
  final bodies = <MapEntry<int, String>>[];

  var i = 0;
  while (i < lines.length) {
    final match = runPattern.firstMatch(lines[i]);
    if (match == null) {
      i++;
      continue;
    }

    final indent = match.group(1)!.length;
    final inline = match.group(2)!.trim();
    if (inline.isNotEmpty && !inlineMarkers.contains(inline)) {
      bodies.add(MapEntry(i + 1, inline));
      i++;
      continue;
    }

    final buffer = StringBuffer();
    var j = i + 1;
    while (j < lines.length) {
      final line = lines[j];
      if (line.trim().isEmpty) {
        j++;
        continue;
      }
      final lineIndent = line.length - line.trimLeft().length;
      if (lineIndent <= indent) break;
      buffer.writeln(line);
      j++;
    }
    bodies.add(MapEntry(i + 1, buffer.toString()));
    i = j;
  }

  return bodies;
}

/// The `owner/repo@ref` of every `uses:` entry, paired with its line number.
List<MapEntry<int, String>> actionUses(Workflow workflow) {
  final pattern = RegExp('''^\\s*uses:\\s*(['"]?)([^'"\\s#]+)\\1''');
  final uses = <MapEntry<int, String>>[];
  for (var i = 0; i < workflow.lines.length; i++) {
    final match = pattern.firstMatch(workflow.lines[i]);
    if (match != null) {
      uses.add(MapEntry(i + 1, match.group(2)!));
    }
  }
  return uses;
}

/// The declared `path:` of every artifact-upload step, keyed to the step's
/// first line so a failure names the offending workflow.
List<MapEntry<String, String>> artifactPaths(Workflow workflow) {
  final results = <MapEntry<String, String>>[];
  final lines = workflow.lines;
  final upload = RegExp(r'uses:.*upload-(pages-)?artifact');
  final path = RegExp(r'''^\s*path:\s*(.+?)\s*$''');
  for (var i = 0; i < lines.length; i++) {
    if (!upload.hasMatch(lines[i])) continue;
    for (var j = i + 1; j < lines.length && j <= i + 12; j++) {
      final match = path.firstMatch(lines[j]);
      if (match != null) {
        results.add(MapEntry('line ${i + 1}', match.group(1)!));
        break;
      }
    }
  }
  return results;
}

/// Slice of [workflow] starting at the step whose name contains [name].
String stepBlock(Workflow workflow, String name, {int span = 16}) {
  final lines = workflow.lines;
  final start = lines.indexWhere((line) => line.contains('name: $name'));
  if (start < 0) return '';
  final end = start + span < lines.length ? start + span : lines.length;
  return lines.sublist(start, end).join('\n');
}

/// The `env:` block of the `google-github-actions/run-gemini-cli` step in
/// [workflow], or an empty string if the workflow has no such step.
String geminiCliEnv(Workflow workflow) {
  final lines = workflow.lines;
  final start = lines.indexWhere((line) => line.contains('run-gemini-cli@'));
  if (start < 0) return '';
  // The `env:` block starts after the `uses:` line and ends at the next
  // key indented no deeper than `env:` itself (`with:`).
  final envIndex = lines.indexWhere((line) => line.trim() == 'env:', start);
  if (envIndex < 0) return '';
  final indent = lines[envIndex].length - lines[envIndex].trimLeft().length;
  final buffer = StringBuffer();
  for (var i = envIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final lineIndent = line.length - line.trimLeft().length;
    if (lineIndent <= indent) break;
    buffer.writeln(line.trim());
  }
  return buffer.toString();
}

void main() {
  final allWorkflows = workflows();

  test('every third-party action is pinned to a full commit SHA', () {
    final pinned = RegExp(r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$');
    final offenders = <String>[];
    for (final workflow in allWorkflows) {
      for (final use in actionUses(workflow)) {
        final target = use.value;
        if (target.startsWith('./') || target.startsWith('docker://')) continue;
        if (!pinned.hasMatch(target)) {
          offenders.add('${workflow.name}:${use.key} uses $target');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Unpinned actions:\n${offenders.join('\n')}');
  });

  test('no GitHub expression is interpolated into a shell body', () {
    final offenders = <String>[];
    for (final workflow in allWorkflows) {
      for (final body in runBodies(workflow)) {
        if (body.value.contains(r'${{')) {
          offenders.add('${workflow.name}:${body.key}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Interpolated expressions in run bodies:\n${offenders.join('\n')}',
    );
  });

  test('the release workflow derives the version code through the pure module',
      () {
    final release = allWorkflows.firstWhere((w) => w.name == 'release.yml');
    expect(release.text, contains('dart tool/version_code.dart'));
    expect(
      release.text,
      isNot(contains('10#')),
      reason: 'versionCode arithmetic must not be re-implemented in shell',
    );
  });

  test('mounted credentials are removed by a step that runs even on failure',
      () {
    final release = allWorkflows.firstWhere((w) => w.name == 'release.yml');
    final cleanup = stepBlock(release, 'Remove mounted credentials');
    expect(cleanup, isNot(isEmpty),
        reason: 'release.yml must keep its cleanup step');
    expect(cleanup, contains('if: always()'));
    for (final path in const [
      'fastlane/play-supply-credentials.json',
      'android/key.properties',
      'android/app/google-services.json',
      r'$HOME/.keystores',
    ]) {
      expect(cleanup, contains(path), reason: 'cleanup must remove $path');
    }
  });

  test('no workflow uploads a broad or dynamic artifact path', () {
    const broad = {'.', './', '/', '*', '**', './*', './**'};
    final offenders = <String>[];
    for (final workflow in allWorkflows) {
      for (final entry in artifactPaths(workflow)) {
        final path = entry.value.replaceAll("'", '').replaceAll('"', '');
        if (path.contains(r'${{') || broad.contains(path)) {
          offenders.add('${workflow.name}: ${entry.key} path=$path');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Broad artifact uploads:\n${offenders.join('\n')}');
  });

  test('no workflow grants an environment-reading shell command', () {
    const environmentReading = {
      'printenv',
      'env',
      'set',
      'export',
      'declare',
      'compgen',
      'typeset',
    };
    final command = RegExp(r'run_shell_command\(\s*([a-z0-9_-]+)\s*\)');
    final offenders = <String>[];
    for (final workflow in allWorkflows) {
      for (final match in command.allMatches(workflow.text)) {
        final name = match.group(1)!.toLowerCase();
        if (environmentReading.contains(name)) {
          offenders.add('${workflow.name}: run_shell_command($name)');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Environment-reading tools granted to agents:\n${offenders.join('\n')}',
    );
  });

  test('triage agents receive no GitHub credential', () {
    const triageWorkflows = {
      'gemini-triage.yml',
      'gemini-scheduled-triage.yml'
    };
    final offenders = <String>[];
    for (final workflow in allWorkflows) {
      if (!triageWorkflows.contains(workflow.name)) continue;
      final env = geminiCliEnv(workflow);
      if (env.isEmpty) {
        offenders.add('${workflow.name}: no run-gemini-cli step found');
        continue;
      }
      if (!env.contains('GITHUB_TOKEN:')) {
        offenders.add(
            '${workflow.name}: triage agent env does not declare GITHUB_TOKEN');
        continue;
      }
      final tokenLine = env
          .split('\n')
          .firstWhere((l) => l.trim().startsWith('GITHUB_TOKEN:'));
      if (!tokenLine.contains("''")) {
        offenders.add(
            '${workflow.name}: triage agent is handed a GitHub credential');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Triage agents must never receive a GitHub credential:\n${offenders.join('\n')}',
    );
  });

  test('the release job stays gated behind the production environment', () {
    final release = allWorkflows.firstWhere((w) => w.name == 'release.yml');
    expect(release.text, contains('environment: production'));
  });
}
