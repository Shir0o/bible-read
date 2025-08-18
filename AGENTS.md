# Agent instructions

This repository hosts a Flutter application. The code you will usually modify lives in the Dart sources under `lib/` and the tests under `test/`.

## Overview of the codebase

- `lib/` – main application code
  - `lib/pages/` contains page widgets like `home_page.dart`
  - `lib/widgets/` contains reusable UI components
  - `lib/firebase_options.dart` configures Firebase and is generated
- `test/` – unit and widget tests

Some parts of the UI are currently being migrated to a more modular widget structure. Focus on the Dart files above rather than the platform specific directories (`android/`, `ios/`, etc.). The `flutter/` directory holds the SDK and **must not be committed**.

## Environment setup

To run Flutter commands, ensure the local Flutter SDK is configured. Follow the steps in [Programmatic checks](#programmatic-checks) to set up the SDK and run formatting, analysis, and tests.

## Cloud Functions

Install Node 20 and run `npm ci` inside the `functions/` directory to set up the dependencies. A typical setup using the NodeSource repository looks like:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
cd functions && npm ci
```

Run `npm run lint` and `npm test` to ensure the Cloud Functions pass linting and unit tests.
- Local tests require `functions/serviceAccount.json`; without it the functions tests will fail.
  This file contains a service account key and must be kept private (ignored by Git).

## Working in `functions/` vs Flutter

The `functions/` directory is a standalone Node project. When modifying files there, run `npm ci`, `npm run lint`, and `npm test` from inside that folder to install dependencies, check code style, and execute the Cloud Functions tests. Keep `node_modules/` out of version control. Everything outside of `functions/` is part of the Flutter application. Edit Dart files from the repository root and use the commands in [Programmatic checks](#programmatic-checks). Avoid mixing Node and Flutter tooling across directories.

## Contribution and style guidelines

- Run the commands in [Programmatic checks](#programmatic-checks) before committing.
- For Cloud Functions changes, run `npm run lint` then `npm test` in `functions/`.
- Follow the lints defined in `analysis_options.yaml`.
- Use `const` constructors when possible and prefer camelCase names.
- Wrap asynchronous work in `try`/`catch` blocks and return `Future<void>`.
- Document public functions with brief comments.

### Exception logging

Caught exceptions should be recorded using `ErrorLogger.log`. Always pass the stack trace when available so Crashlytics receives full context. After adding or updating logging, run the commands in the [Programmatic checks](#programmatic-checks) section to verify formatting, lints, and tests.

### Parts being migrated

The pages in `lib/pages` are gradually being broken into smaller widgets found in `lib/widgets`. When adding features prefer creating a widget in the widgets folder and composing pages from those widgets.

## Programmatic checks

Run the following commands to set up the Flutter SDK, format the code, analyze it, and execute all tests:

```bash
./scripts/setup_flutter.sh
dart format lib test
flutter analyze
flutter test --no-pub
```

If you modify Cloud Functions code in `functions/`, run `npm run lint` and `npm test` in that directory to verify linting and tests as well. If your change does not modify any code (e.g., documentation updates), you may skip running tests.

## Agent workflow

- Explore `README.md` and existing Dart sources for context before editing.
- Write or update documentation when introducing new features or behaviour.
- Summarize changes and reference file paths in the PR description.
- Include a "Testing" section in the PR with the results of running the checks above.

## Running tests in Codex

In Codex, run the commands in [Programmatic checks](#programmatic-checks). If the full Flutter test suite exceeds the session limit, execute a minimal subset of tests (e.g., `flutter test --no-pub test/widget_test.dart`) or run the full suite locally.

