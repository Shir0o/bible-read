# Golden Tests

This directory contains visual regression tests.

To run golden tests:
`flutter test test/goldens`

To update golden files (when UI changes intentionally):
`flutter test --update-goldens test/goldens`

**Note:** Golden files are platform-dependent (Mac vs Linux vs Windows).
Ensure you run/update them on the same platform as your CI/team standard.
