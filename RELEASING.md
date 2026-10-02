# Releasing Bible Reading Challenge

This document describes the release pipeline that ships Android APK + AAB
and iOS IPA artifacts to GitHub Releases, to the Google Play Console **internal
testing** track, and to Apple **TestFlight**. Production promotion remains a manual step
in the respective store consoles. The pipeline mirrors the one in [`~/attd`](https://github.com/Shir0o/attd)
and [`cisa-campus-work-tracker`](https://github.com/Shir0o/cisa-campus-work-tracker).

For the rationale behind each choice (release-please vs. alternatives,
internal-track-first, Play App Signing, App Store Connect API Key, etc.) see
[`docs/adr/0001-release-automation.md`](docs/adr/0001-release-automation.md) and
[`docs/adr/0009-ios-testflight-release-automation.md`](docs/adr/0009-ios-testflight-release-automation.md).

## How a release happens

1. A conventional-commit PR (e.g. `feat:`, `fix:`) lands on `main`.
   The title carries the conventional-commit signal — release-please
   reads **PR titles**, not commit messages.
2. The `.github/workflows/release-please.yml` workflow opens or updates a
   **release PR**. The PR bumps `pubspec.yaml` (bare semver, e.g.
   `1.26.0`) and regenerates `CHANGELOG.md`. The numeric build number is
   derived from the tag at build time (`major*10000 + minor*100 + patch`,
   e.g. `v1.26.0` → `12600`).
3. You review the release PR (check the changelog draft and the version
   bump), then merge it.
4. The merge pushes a tag (e.g. `v1.26.0`). Two release workflows fire in parallel:
   - **Android (`.github/workflows/release.yml`)**:
     - Assembles `key.properties` from secrets.
     - Derives `versionCode` using `tool/version_code.dart`.
     - Builds signed AAB + APK with `--build-number="$VERSION_CODE"`.
     - Attaches both to the GitHub Release.
     - Uploads the AAB to Play Console internal testing track via `fastlane play_upload` as draft.
   - **iOS (`.github/workflows/release-ios.yml`)**:
     - Installs the Apple Distribution certificate and mobileprovision profile into a temporary CI keychain.
     - Materializes the App Store Connect API key (`.p8`).
     - Builds signed IPA with `--build-number="$VERSION_CODE"`.
     - Attaches the IPA to the GitHub Release.
     - Uploads the IPA to TestFlight via `fastlane ios testflight_upload`.
5. **You** open the Play Console and TestFlight, verify the builds on internal tracks,
   and promote to Production when ready.

That's the whole flow. There is no manual version bump, no manual tag,
no manual upload.

## Security model

The pipeline treats everything it consumes as data and gives the runner as
little to execute as possible:

- **Tag-as-data.** Workflow steps read the tag from the `TAG` environment
  variable. No `${{ }}` expression is interpolated into a `run:` shell body
  anywhere under `.github/workflows/`; the invariant is asserted by
  `test/release/workflow_security_test.dart`.
- **Pure version derivation.** `tool/version_code.dart` owns the
  `major * 10000 + minor * 100 + patch` contract. It accepts only
  `v?MAJOR.MINOR.PATCH` with an optional `-prerelease` suffix and rejects
  anything else (leading zeros, build metadata, shell metacharacters, values
  that would overflow the Android limit). The workflow calls the module
  instead of re-implementing the arithmetic in shell.
- **Immutable action pins.** Every third-party `uses:` is pinned to a full
  40-character commit SHA with a version comment. Dependabot
  (`.github/dependabot.yml`, `github-actions` ecosystem) raises the pin
  updates, so pinning does not freeze dependencies.
- **Automated release deployment.** The `build-and-publish` job triggers
  automatically upon merging the release-please PR (which creates the `v*` tag)
  and publishes directly to the Play Console internal testing track.
- **Short-lived tokens.** `release.yml` attaches release assets with the
  workflow's own `GITHUB_TOKEN`. The long-lived `RELEASE_PLEASE_TOKEN` is
  used only by `.github/workflows/release-please.yml`, where a token that
  can trigger the downstream `on: push: tags` workflow is genuinely required.
- **Credential lifecycle.** Every file written from a secret
  (`fastlane/play-supply-credentials.json`, `android/key.properties`,
  `android/app/google-services.json`, and `~/.keystores`) is deleted by a
  step guarded with `if: always()`, so a failed release does not leave
  credentials in the workspace.
- **Narrow artifacts.** No workflow uploads the working tree; artifact paths
  are enumerated explicitly.

## PR title conventions (required)

The lint workflow `.github/workflows/pr-title-lint.yml` rejects PRs whose
titles don't match a conventional-commit prefix. Allowed prefixes:

| Prefix            | Effect                                |
| ----------------- | ------------------------------------- |
| `feat:`           | Minor bump; lands under "Features"    |
| `feat!:`          | Major bump; lands under "Features"    |
| `fix:`            | Patch bump; lands under "Bug Fixes"   |
| `perf:`           | Patch bump; lands under "Performance" |
| `refactor:`       | No bump; lands under "Refactoring"    |
| `docs:`, `test:`, `build:`, `ci:`, `chore:`, `revert:` | Hidden from changelog (still allowed) |

`BREAKING CHANGE:` in the PR body footer also triggers a major bump.

## Prerequisites (one-time setup)

The pipeline needs seven GitHub secrets. None of them are committed;
create them under **Settings → Secrets and variables → Actions**:

### Android Secrets

| Secret                  | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `RELEASE_PLEASE_TOKEN`  | Fine-grained PAT scoped to **this repository only** with `Contents: write` and `Pull requests: write`. **Required** because tags created with the built-in `GITHUB_TOKEN` are suppressed by GitHub Actions and would never trigger the downstream `release.yml` workflow. `release.yml` no longer consumes this PAT; it attaches assets with the short-lived `GITHUB_TOKEN`. |
| `ANDROID_KEYSTORE_BASE64` | `base64` of the CI **upload** keystore (`~/.keystores/my-key.keystore` on this machine). |
| `KEY_ALIAS`             | Alias of the upload key inside the keystore.                            |
| `KEY_PASSWORD`          | Password for the upload key.                                            |
| `STORE_PASSWORD`        | Password for the keystore file itself.                                  |
| `PLAY_SUPPLY_JSON_KEY`  | Contents of the Play Console service-account JSON (release-manager).    |
| `GOOGLE_SERVICES_JSON`  | Contents of `android/app/google-services.json`. The Google Services Gradle plugin requires this at build time; mounted from this secret at workflow runtime, never logged. |

### iOS Secrets

| Secret                            | Purpose                                                                 |
| --------------------------------- | ----------------------------------------------------------------------- |
| `IOS_DISTRIBUTION_CERT_BASE64`    | `base64` of Apple Distribution `.p12` certificate.                      |
| `IOS_CERT_PASSWORD`               | Password for the `.p12` certificate.                                   |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64` of App Store distribution provisioning profile (`.mobileprovision`). |
| `ASC_API_KEY_P8_BASE64`           | `base64` of the App Store Connect API Key (`AuthKey_*.p8`).             |
| `ASC_KEY_ID`                      | 10-character Key ID from App Store Connect.                             |
| `ASC_ISSUER_ID`                   | Issuer ID (UUID) from App Store Connect Users and Access → Integrations. |

> **Important:** `RELEASE_PLEASE_TOKEN` is mandatory for end-to-end automation, but is required
> *only* by `release-please.yml`. While `GITHUB_TOKEN` has permission to create tags, GitHub's
> recursion prevention stops tags it creates from firing downstream `on: push: tags` workflows.
> Keep the PAT scoped to this repository and to `contents:write` + `pull-requests:write` only.

All secrets are seeded under **Settings → Secrets and variables → Actions** or via `gh secret set`:

```bash
# Android
base64 -i ~/.keystores/my-key.keystore | tr -d '\n' | \
  gh secret set ANDROID_KEYSTORE_BASE64 --repo Shir0o/bible-read
gh secret set KEY_ALIAS --repo Shir0o/bible-read --body "my-key-alias"
gh secret set KEY_PASSWORD --repo Shir0o/bible-read --body "<your-key-password>"
gh secret set STORE_PASSWORD --repo Shir0o/bible-read --body "<your-store-password>"
gh secret set PLAY_SUPPLY_JSON_KEY --repo Shir0o/bible-read < ~/release-please-supply-key.json
gh secret set GOOGLE_SERVICES_JSON --repo Shir0o/bible-read < android/app/google-services.json

# iOS
base64 -i ~/certs/distribution.p12 | tr -d '\n' | \
  gh secret set IOS_DISTRIBUTION_CERT_BASE64 --repo Shir0o/bible-read
gh secret set IOS_CERT_PASSWORD --repo Shir0o/bible-read --body "<your-cert-password>"
base64 -i ~/certs/BibleRead_AppStore.mobileprovision | tr -d '\n' | \
  gh secret set IOS_PROVISIONING_PROFILE_BASE64 --repo Shir0o/bible-read
base64 -i ~/certs/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | \
  gh secret set ASC_API_KEY_P8_BASE64 --repo Shir0o/bible-read
gh secret set ASC_KEY_ID --repo Shir0o/bible-read --body "XXXXXXXXXX"
gh secret set ASC_ISSUER_ID --repo Shir0o/bible-read --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Play Console service-account JSON

1. Open Google Cloud Console → IAM & Admin → Service Accounts.
2. Create a service account (no GCP-side role needed — Play Console
   manages its own grants).
3. Create a JSON key, download it, paste its contents as the
   `PLAY_SUPPLY_JSON_KEY` secret value:

```bash
gh secret set PLAY_SUPPLY_JSON_KEY --repo Shir0o/bible-read < ~/path/to/key.json
```

4. In **Play Console → Settings → API access**, link the service
   account and grant it the **Release Manager** permission (account-wide
   grants cover every app in the developer account).

## Troubleshooting

| Symptom                                                | Likely cause                                                  |
| ------------------------------------------------------ | -------------------------------------------------------------- |
| `release.yml` fails on secret check                    | One of the required secrets is empty/missing in repo settings. |
| Play Console upload fails with "versionCode not higher than previous" | Two tags have the same `major*10000 + minor*100 + patch`. Don't re-tag without bumping. |
| Play Console upload fails with "package not found"     | The applicationId `com.bibleread.challenge` does not match the Play Console listing. Update the Fastfile `APP_PACKAGE_NAME` to match. |
| Play Console upload fails with "permission denied" / 403 | The service account named in `PLAY_SUPPLY_JSON_KEY` has not been granted Release Manager on the Play Console for this app. Re-link it. |
| `bundle exec fastlane play_upload` fails to install    | Ruby/Bundler missing on the runner — the workflow installs them via `bundle install`. If your fork uses an older Ubuntu image, the system Ruby may be too old; pin `ruby-version: 3.2` in `release.yml`. |
| Internal-track upload succeeds but AAB is wrong        | Play Console internal track allows removal — go to Release management → Internal testing, find the version, click **Discard**. Re-run the workflow with the corrected tag. |
| Local `flutter run` fails with INSTALL_FAILED_VERSION_DOWNGRADE | pubspec no longer carries `+buildNumber`; pass `--build-number` locally (e.g. `flutter run --build-number=99999`) or uninstall the old app once. |

## Rolling back a release

- **GitHub Release**: delete the tag (`git push --delete origin v1.26.0`
  + delete the release UI). The release-please bot will not re-cut it.
- **Play Console internal track**: discard the release in the Play
  Console UI. No app-store review, takes effect immediately.
- **Play Console production**: use the Play Console "Halt rollout" button.
  This stops the rollout but the version stays in the Play listing until
  you disable it.

## Pre-release tags

A tag matching `*-rc*` or `*-beta*` (e.g. `v1.27.0-rc1`) still builds
APK + AAB and attaches them to a GitHub pre-release, but **skips** the
Play Console upload. Use this for external testers who sideload.

## Rehearsing a hostile tag

To demonstrate end-to-end that a crafted tag executes nothing:

1. In a scratch fork with **no release secrets configured**, push a tag such
   as `v1.2.3;echo pwned`.
2. Confirm the run stops at the tag validation step (the pure module rejects
   the tag before any shell sees it).
3. Confirm no step logged the tag as executable code and no upload ran.

This rehearsal is manual because it requires pushing a tag; the module's
rejection table and the workflow invariants cover the regression path in CI.

## Local equivalent

If you need to ship a one-off from your laptop (without waiting for CI):

```bash
flutter build appbundle --release   # uses your local android/key.properties
flutter build apk --release
# Then upload the AAB manually in the Play Console UI.
```

The CI pipeline is the **canonical** path; the local equivalent is only
for emergencies.

## Bootstrap note (2026-09)

The repo's pre-pipeline tags (`1.18.0+19`, `1.19.0+20`) used a different
format; release-please owns `v*` tags from now on. The baseline tag
`v1.25.0` was pushed manually once to seed release-please's manifest —
its `release.yml` run was the pipeline's first end-to-end validation.
