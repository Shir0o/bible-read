# Agent instructions

This repository hosts a Flutter application. The code you will usually modify
lives in the Dart sources under `lib/` and the tests under `test/`.

## Overview of the codebase

- `lib/` – main application code
  - `lib/pages/` contains page widgets like `home_page.dart`
  - `lib/widgets/` contains reusable UI components
  - `lib/firebase_options.dart` configures Firebase and is generated
- `test/` – unit and widget tests

Some parts of the UI are currently being migrated to a more modular widget
structure. Focus on the Dart files above rather than the platform specific
directories (`android/`, `ios/`, etc.). The `flutter/` directory holds the SDK
and **must not be committed**.

## Environment setup

To run Flutter commands in this repository, the Codex environment must set up
the local Flutter SDK. Run the provided script to clone the repository, add the
SDK to `PATH`, disable analytics, accept Android licenses, and fetch
dependencies:

```bash
./scripts/setup_flutter.sh
```

## Cloud Functions

Install Node 20 and run `npm ci` inside the `functions/` directory to set up the
dependencies. A typical setup using the NodeSource repository looks like:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
cd functions && npm ci
```

Run `npm run lint` and `npm test` to ensure the Cloud Functions pass linting and unit tests.
- Local tests require `functions/serviceAccount.json`; without it the functions tests will fail.
  This file contains a service account key and must be kept private (ignored by Git).

## Working in `functions/` vs Flutter

The `functions/` directory is a standalone Node project. When modifying files
there, run `npm ci`, `npm run lint`, and `npm test` from inside that folder to
install dependencies, check code style, and execute the Cloud Functions tests. Keep
`node_modules/` out of version control. Everything outside of `functions/` is
part of the Flutter application. Edit Dart files from the repository root and
use `dart format`, `flutter analyze`, and `flutter test`
as outlined below. Avoid mixing Node and Flutter tooling across directories.

## Contribution and style guidelines

- Format Dart code with `dart format lib test` before committing.
- Follow the lints defined in `analysis_options.yaml`; run `flutter analyze` to
  verify there are no warnings.
- Ensure all relevant tests pass before committing; run `flutter test --no-pub`
  for Flutter code and `npm run lint` then `npm test` in `functions/` for Cloud Functions changes.
- Use `const` constructors when possible and prefer camelCase names.
- Wrap asynchronous work in `try`/`catch` blocks and return `Future<void>`.
- Document public functions with brief comments.

### Exception logging

Caught exceptions should be recorded using `ErrorLogger.log`. Always pass the stack trace when available so Crashlytics receives full context. After adding or updating logging, run the commands in the [Programmatic checks](#programmatic-checks) section to verify formatting, lints, and tests.

### Parts being migrated

The pages in `lib/pages` are gradually being broken into smaller widgets found
in `lib/widgets`. When adding features prefer creating a widget in the widgets
folder and composing pages from those widgets.

## Programmatic checks

Run `./scripts/setup_flutter.sh` once so the Flutter SDK is on your `PATH`
before running lints or tests. After the setup completes, run the following
commands to format the code, analyze it, and execute all tests:

```bash
dart format lib test
flutter analyze
flutter test --no-pub
```

If you modify Cloud Functions code in `functions/`, run `npm run lint` and
`npm test` in that directory to verify linting and tests as well.


## Agent workflow

- Explore `README.md` and existing Dart sources for context before editing.
- Write or update documentation when introducing new features or behaviour.
- Summarize changes and reference file paths in the PR description.
- Include a "Testing" section in the PR with the results of running the checks
  above.

## Running tests in Codex

To run fast, essentials-only tests in Codex:


1. **Set up Flutter SDK and dependencies** (first time only):
   ```bash
   ./scripts/setup_flutter.sh
   ```

2. **Run tests**:
   ```bash
   flutter test --no-pub
   ```
   A full run of `flutter test --no-pub` typically exceeds Codex's 1-minute
   session limit. In such restricted environments, run only a minimal subset
   of tests (for example, `flutter test --no-pub test/widget_test.dart`) or
   skip tests here and execute the full suite locally instead.

### Tips for faster runs

- Use `--no-pub` to skip dependency checks when re-running.
- Only unit/widget tests are run—no emulator/device needed.
- Cache `.pub-cache/` and `flutter/bin/cache` to avoid re-downloading.
