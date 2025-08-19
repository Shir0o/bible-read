# Quick fix command

In extremely time-limited environments (around one minute), the following combined command performs minimal checks safely:

```bash
git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter && \
export PUB_CACHE="$PWD/.pub-cache" && \
export PATH="$PWD/flutter/bin:$PATH" && \
flutter config --no-analytics && \
flutter pub get && \
dart format lib test && \
flutter analyze && \
flutter test --no-pub test/widget_test.dart
```

This installs the Flutter SDK, formats Dart sources, runs static analysis, and executes a fast widget test to catch obvious issues without running the full suite.
