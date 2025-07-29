# Test Coverage

To generate coverage data for the Dart tests run:

```bash
flutter test --coverage
```

This produces `coverage/lcov.info`.

The repository ignores the generated `coverage/` directory so you will
usually view the reports locally or copy them elsewhere.

If you have the `lcov` tools installed you can build an HTML report:

```bash
# sudo apt-get install lcov
genhtml coverage/lcov.info --output-directory coverage/html
```

Open `coverage/html/index.html` in a browser to explore the report.
