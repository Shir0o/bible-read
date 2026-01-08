# Agent instructions

TL;DR: Focus on the Dart sources in `lib/` and tests in `test/`, run the quick Flutter setup below before checks, and keep generated SDK artifacts such as `flutter/` out of commits.

This repository hosts a Flutter application. The code you will usually modify lives in the Dart sources under `lib/` and the tests under `test/`.

## Overview of the codebase

- `lib/` – main application code
  - `lib/pages/` contains page widgets like `home_page.dart`
  - `lib/widgets/` contains reusable UI components
  - `lib/firebase_options.dart` configures Firebase and is generated
- `test/` – unit and widget tests

Some parts of the UI are currently being migrated to a more modular widget structure. Focus on the Dart files above rather than the platform specific directories (`android/`, `ios/`, etc.). The `flutter/` directory holds the SDK and **must not be committed**.

## Environment setup

### Quick start

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

### Optional caching tips

The `flutter` directory holds the SDK and **must not be committed**. To speed up repeated runs, copy back cached artifacts after cloning:

- Set `FLUTTER_BIN_CACHE` to a cached `flutter/bin/cache` directory before cloning, then restore it into place.
- Preserve your Dart packages by keeping `.pub-cache` (or setting `PUB_CACHE_SRC`) and syncing it back once the quick start steps finish.

For documentation-only updates (e.g., changes limited to `.md` files), you do not need to clone this repository, install Flutter, or run any of the setup commands in this section.

## Cloud Functions

The `functions/` directory is a standalone Node.js project separate from the Flutter app. Only dive in when a feature needs backend triggers, scheduled jobs, or shared validation that cannot live in Flutter; most day-to-day feature work remains in `lib/`.

When you do need Cloud Functions, bootstrap the project with:

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
- Request the Firebase service account credentials (`functions/serviceAccount.json`) from the project maintainers and store them outside version control; copy the file in locally when running tests.
- Use Node tooling only inside `functions/`; run Flutter commands from the repository root for Dart code.

## Contribution and style guidelines

- Run the commands in [Programmatic checks](#programmatic-checks) before committing.
- Ensure new code is formatted with `dart format --fix` and that `flutter analyze` reports no warnings or errors before submission.
- For Cloud Functions changes, run `npm run lint` then `npm test` in `functions/`.
- Follow the lints defined in `analysis_options.yaml`.
- Use `const` constructors when possible and prefer camelCase names.
- Wrap asynchronous work in `try`/`catch` blocks and return `Future<void>`.
- Document public functions with brief comments.

## Material 3 Design Guidelines

- **Strict No-Hex Policy**: Do not use custom hex codes for colors (e.g., `Color(0xFF...)`) or hardcoded constants (e.g. `Colors.green`) unless explicitly requested by the user.
- **Use Material Tokens**: Always use the default classes provided by Material 3 Expressive, such as `md.sys.color.primary` (mapped to `Theme.of(context).colorScheme.primary` in Flutter).
- **Avoid Hardcoding**: Do not hardcode structure colors. Use semantic tokens like `colorScheme.surface`, `colorScheme.onSurfaceVariant`, `colorScheme.outline`, etc.

## Error handling & logging

- Use the shared logger in `lib/services/error_logger.dart` by calling `ErrorLogger.log(error, stackTrace)` from catch blocks or platform hooks.
- Always forward the stack trace when available so Firebase Crashlytics receives full context.
- Crashlytics collection is disabled in debug builds; to verify logging, run a profile or release build (or temporarily enable collection in debug), trigger a test exception such as `FirebaseCrashlytics.instance.crash()`, and confirm the event in the Firebase console.

## Parts being migrated

The pages in `lib/pages` are gradually being broken into smaller widgets found in `lib/widgets`. When adding features prefer creating a widget in the widgets folder and composing pages from those widgets.

## Programmatic checks

For documentation-only changes (e.g., `.md` files), you do not need to run `dart format`, `flutter analyze`, or `flutter test`.

Checklist with rough runtimes:

- `dart format --fix lib test` (~5s) – keep code style consistent; skip for docs-only work.
- `flutter analyze` (~15s) – must be clean before committing.
- `flutter test --no-pub --fail-fast` (~1–2 min) – run the full suite when feasible or target only the impacted tests when time-constrained.

Run the following commands to format the code, analyze it, and execute all tests:

```bash
dart format --fix lib test
flutter analyze
flutter test --no-pub --fail-fast
```

Only commit changes once `flutter analyze` reports no issues, every relevant test suite passes, and `flutter test --no-pub --fail-fast` completes without failures. Ensure that sufficient automated tests covering the modified behaviour are present or updated before committing.

If you modify Cloud Functions code in `functions/`, run `npm run lint` and `npm test` in that directory to verify linting and tests as well.

## Agent workflow

- Explore `README.md` and existing Dart sources for context before editing.
- Write or update documentation when introducing new features or behaviour.
- Summarize changes and reference file paths in the PR description.
- Include a "Testing" section in the PR with the results of running the checks above.

## Running tests in Codex

In Codex, run the commands in [Programmatic checks](#programmatic-checks). If the full Flutter test suite exceeds the session limit, execute a minimal subset of tests (e.g., `flutter test --no-pub test/widget_test.dart`) or run the full suite locally.

For a one-minute command performing basic checks, see [docs/quick_fix.md](docs/quick_fix.md).

## Common pitfalls

- Never commit the local Flutter SDK (`flutter/`), platform build outputs, or `functions/node_modules/` – keep the repo clean.
- Check for a dirty worktree before editing and avoid reverting changes you didn't make.
- Keep real credentials (e.g., `functions/serviceAccount.json`) out of version control; request them and add them locally when needed.
- When enabling Crashlytics or other temporary debugging changes, undo them before opening a PR.
