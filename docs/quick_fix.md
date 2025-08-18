# Quick fix command

In extremely time-limited environments (around one minute), the following combined command performs minimal checks safely:

```bash
./scripts/setup_flutter.sh && dart format lib test && flutter analyze && flutter test --no-pub test/widget_test.dart
```

This installs the Flutter SDK, formats Dart sources, runs static analysis, and executes a fast widget test to catch obvious issues without running the full suite.
