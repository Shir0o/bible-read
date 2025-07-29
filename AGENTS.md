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
the local Flutter SDK. The setup script should clone the Flutter repository, add
the SDK to the `PATH`, and fetch dependencies.

```
# 1. Install Flutter SDK (locally in the project)
#    This clones the stable branch to a subdirectory named `flutter`.
git clone https://github.com/flutter/flutter.git -b stable flutter

# 2. Add Flutter to PATH
export PATH="$PWD/flutter/bin:$PATH"

# Run Flutter doctor to download artifacts and check the tool chain
flutter doctor

# Accept Android licenses without interactive prompts
yes | flutter doctor --android-licenses || true

# 3. Get project dependencies
flutter pub get
```

## Contribution and style guidelines

- Format Dart code with `flutter format .` before committing.
- Follow the lints defined in `analysis_options.yaml`; run `flutter analyze` to
  verify there are no warnings.
- Use `const` constructors when possible and prefer camelCase names.
- Wrap asynchronous work in `try`/`catch` blocks and return `Future<void>`.
- Document public functions with brief comments.

### Parts being migrated

The pages in `lib/pages` are gradually being broken into smaller widgets found
in `lib/widgets`. When adding features prefer creating a widget in the widgets
folder and composing pages from those widgets.

## Programmatic checks

Make sure the Flutter SDK is installed and on your `PATH` before running lints
or tests. After performing the environment setup above run:

```bash
flutter format .
flutter analyze
flutter test
flutter test --coverage
```

After running the tests with coverage, review the generated `coverage/lcov.info`
file and ensure overall coverage stays above **80%**.

## Agent workflow

- Explore `README.md` and existing Dart sources for context before editing.
- Write or update documentation when introducing new features or behaviour.
- Summarize changes and reference file paths in the PR description.
- Include a "Testing" section in the PR with the results of running the checks
  above.

## Running tests with coverage in Codex

To run fast, essentials-only tests with coverage in Codex:

1. **Install `lcov`** (only needed once):
   ```bash
   sudo apt-get update && sudo apt-get install -y lcov
   ```

2. **Set up Flutter SDK and dependencies** (first time only):
   ```bash
   git clone https://github.com/flutter/flutter.git -b stable flutter
   export PATH="$PWD/flutter/bin:$PATH"

   yes | flutter doctor --android-licenses || true
   flutter doctor

   flutter pub get
   ```

3. **Run tests with coverage**:
   ```bash
   flutter test --no-pub --coverage --coverage-path=coverage/lcov.info
   ```

   This generates a `coverage/lcov.info` file. You can use this with coverage tools (e.g. Codecov, Coveralls).

### Tips for faster runs

- Use `--no-pub` to skip dependency checks when re-running.
- Only unit/widget tests are run—no emulator/device needed.
- Cache `.pub-cache/` and `flutter/bin/cache` to avoid re-downloading.
