# Test Coverage

To generate coverage data for the Dart tests run:

```bash
flutter test --no-pub --coverage --coverage-path=coverage/lcov.info
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

## Functions Coverage

The Firebase Cloud Functions under `functions/` have their own tests and
coverage task. From the `functions` directory run:

```bash
npm ci
npm run coverage
```

The `coverage` script uses `nyc` to generate reports in
`functions/coverage/`, including an `lcov.info` file and HTML output.

## Combined Flutter and Functions Coverage

To view overall coverage, merge the Flutter and Cloud Functions reports.
Use `lcov` to add the two `lcov.info` files together and write the
combined output:

```bash
lcov -a coverage/lcov.info -a functions/coverage/lcov.info -o coverage/merged.lcov.info
```

Generate an HTML report from the merged data:

```bash
genhtml coverage/merged.lcov.info --output-directory coverage/html
```

Open `coverage/html/index.html` in a browser to explore the combined
coverage report.
