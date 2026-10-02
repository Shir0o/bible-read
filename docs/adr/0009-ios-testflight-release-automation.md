# ADR 0009: iOS and TestFlight release automation pipeline

- Status: Accepted
- Date: 2026-10-02
- Mirrors: [`Shir0o/attd` ADR 0001](https://github.com/Shir0o/attd/blob/main/docs/adr/0001-release-automation.md), [`cisa-campus-work-tracker` `release-ios.yml`](https://github.com/Shir0o/cisa-campus-work-tracker/blob/main/.github/workflows/release-ios.yml)

## Context

Android release automation was established in [ADR 0001](0001-release-automation.md) using release-please, fastlane supply, and derived versionCodes from git tags. iOS builds, however, had no CI/CD pipeline or automated upload to TestFlight. Deploying iOS required local macOS execution, manual code signing configuration, and manual IPA uploads.

## Decision

We adopt an automated iOS release pipeline that mirrors the Android release model while adapting to Apple Developer and TestFlight standards:

1. **Dedicated workflow (`.github/workflows/release-ios.yml`)**:
   Runs on `macos-15` runners. Fires automatically on release-please version tags (`v*`) and supports `workflow_dispatch` (for retrying a release against an existing tag without burning a new semver).
2. **Deterministic Code Signing via GitHub Secrets**:
   Following the pattern from `cisa-campus-work-tracker`, the Apple Distribution certificate (`.p12`) and App Store provisioning profile are base64-encoded and securely mounted into a temporary CI keychain during the build, which is deleted upon completion.
3. **App Store Connect API Key for TestFlight Upload**:
   Authentication to App Store Connect uses an App Store Connect API Key (`.p8` private key with Key ID and Issuer ID) via fastlane's `app_store_connect_api_key`. This eliminates SMS 2FA hurdles and headless CI timeouts.
4. **Fastlane Delivery (`ios testflight_upload`)**:
   Flutter CLI builds the release archive (`flutter build ipa --release --build-number="$VERSION_CODE"`), and Fastlane handles upload to TestFlight via `upload_to_testflight` with `skip_waiting_for_build_processing: true` and `skip_submission: true`.
5. **Auto-Compliance**:
   `ITSAppUsesNonExemptEncryption` is set to `<false/>` in `ios/Runner/Info.plist` to prevent TestFlight builds from stalling in "Missing Compliance".
6. **Unified Artifact Attachment**:
   The generated `.ipa` is uploaded as an asset to the corresponding GitHub Release via `gh release upload`, keeping parity with `.apk` and `.aab` attachments.

## Consequences

### Positive

- iOS builds and TestFlight distribution occur automatically alongside Android upon merging a release-please PR.
- Zero manual intervention needed to push new builds to internal TestFlight testers.
- Adheres to the established security invariants: no shell expression injection, pinned third-party actions, pure version derivation via `tool/version_code.dart`, and strict `if: always()` credential cleanup.

### Negative

- Requires provisioning and maintaining six iOS-specific GitHub secrets (`IOS_DISTRIBUTION_CERT_BASE64`, `IOS_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `ASC_API_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`).
- macOS GitHub Actions runners consume higher action minute quotas than Linux runners.

## References

- Release workflow: [`.github/workflows/release-ios.yml`](../../.github/workflows/release-ios.yml)
- Android counterpart: [`docs/adr/0001-release-automation.md`](0001-release-automation.md)
- Fastlane configuration: [`fastlane/Fastfile`](../../fastlane/Fastfile)
- Operations guide: [`RELEASING.md`](../../RELEASING.md)
