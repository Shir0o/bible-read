# Golden Tests

This directory contains visual regression tests.

To run golden tests:
`flutter test test/goldens`

To update golden files (when UI changes intentionally):
`flutter test --update-goldens test/goldens`

**Note:** Golden files are platform-dependent (Mac vs Linux vs Windows).
The committed goldens are rendered on Linux with the current Flutter stable
release (the CI platform), so run and update them on Linux only. Failure diffs
are written to `failures/`, which is git-ignored.
