# Quick fix command

In extremely time-limited environments (around one minute), the following combined command performs minimal checks safely:

```bash
export PUB_CACHE="$PWD/.pub-cache" && \
export PATH="$HOME/flutter/bin:$PATH" && \
flutter config --no-analytics && \
flutter pub get && \
dart format lib test && \
flutter analyze && \
flutter test --no-pub test/widget_test.dart
```

This sets up the Flutter environment, formats Dart sources, runs static analysis, and executes a fast widget test to catch obvious issues without running the full suite.
