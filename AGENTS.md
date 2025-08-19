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

Clone the Flutter SDK and add it to the path before running checks:

```bash
git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
export PUB_CACHE="$PWD/.pub-cache"
export PATH="$PWD/flutter/bin:$PATH"
flutter --version
flutter config --no-analytics
yes | flutter doctor --android-licenses || true
flutter pub get
```

The `flutter` directory holds the SDK and **must not be committed**. To speed up repeated runs you may preserve the `flutter/bin/cache` and `.pub-cache` directories by setting `FLUTTER_BIN_CACHE` and `PUB_CACHE_SRC` to cached locations and copying them back after the commands above.

## Cloud Functions

The `functions/` directory is a standalone Node.js project separate from the Flutter app. When working there:

```bash
# install Node 20 (example using NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
cd functions
npm ci
npm run lint
npm test
```

- Keep `functions/node_modules/` out of version control.
- Local tests require `functions/serviceAccount.json`, which must remain private.
- Use Node tooling only inside `functions/`; run Flutter commands from the repository root for Dart code.

## Contribution and style guidelines

- Run the commands in [Programmatic checks](#programmatic-checks) before committing.
- Ensure new code is formatted with `dart format --fix` and that `flutter analyze` reports no warnings or errors before submission.
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

Run the following commands to format the code, analyze it, and execute all tests:

```bash
dart format --fix lib test
flutter analyze
flutter test --no-pub
flutter test --coverage
lcov --remove coverage/lcov.info 'lib/firebase_options.dart' -o coverage/lcov.info
lcov --list coverage/lcov.info
```

Every file should maintain at least 95% coverage.

Only commit changes once `flutter analyze` reports no issues.

If you modify Cloud Functions code in `functions/`, run `npm run lint` and `npm test` in that directory to verify linting and tests as well. If your change does not modify any code (e.g., documentation updates), you may skip running tests.

## Agent workflow

- Explore `README.md` and existing Dart sources for context before editing.
- Write or update documentation when introducing new features or behaviour.
- Summarize changes and reference file paths in the PR description.
- Include a "Testing" section in the PR with the results of running the checks above.

## Running tests in Codex

In Codex, run the commands in [Programmatic checks](#programmatic-checks). If the full Flutter test suite exceeds the session limit, execute a minimal subset of tests (e.g., `flutter test --no-pub test/widget_test.dart`) or run the full suite locally.

For a one-minute command performing basic checks, see [docs/quick_fix.md](docs/quick_fix.md).

