# Integration Tests

This directory contains end-to-end integration tests that run on a real device or emulator.

## Running Tests

To run the smoke test:
`flutter test integration_test/app_test.dart`

**Note:** These tests interact with the configured Firebase project.
Ensure you are using a test project or Firebase Emulators to avoid affecting production data.
