# Releasing Bible Reading Challenge

This document describes the release pipeline that ships Android APK + AAB
artifacts to GitHub Releases and to the Google Play Console **internal
testing** track. Production promotion remains a manual step in the Play
Console UI. The pipeline mirrors the one in [`~/attd`](https://github.com/Shir0o/attd)
(see its [`RELEASING.md`](https://github.com/Shir0o/attd/blob/main/RELEASING.md)).

For the rationale behind each choice (release-please vs. alternatives,
internal-track-first, Play App Signing, etc.) see
[`docs/adr/0001-release-automation.md`](docs/adr/0001-release-automation.md).

## How a release happens

1. A conventional-commit PR (e.g. `feat:`, `fix:`) lands on `main`.
   The title carries the conventional-commit signal — release-please
   reads **PR titles**, not commit messages.
2. The `.github/workflows/release-please.yml` workflow opens or updates a
   **release PR**. The PR bumps `pubspec.yaml` (bare semver, e.g.
   `1.26.0`) and regenerates `CHANGELOG.md`. The Android `versionCode` is
   derived from the tag by the `release.yml` workflow at build time
   (`major*10000 + minor*100 + patch`, e.g. `v1.26.0` → `12600`). Note
   this replaces the old manually-managed `+buildNumber` in pubspec
   (`1.25.0+26`); the tag-derived versionCode (12500+) is already past
   every legacy build number shipped to the Play Console.
3. You review the release PR (check the changelog draft and the version
   bump), then merge it.
4. The merge pushes a tag (e.g. `v1.26.0`). The
   `.github/workflows/release.yml` workflow fires:
   - Assembles `key.properties` from secrets.
   - Derives the `versionCode` from the tag.
   - Builds a signed AAB and a signed APK with `--build-number=$vc`.
   - Attaches both to the GitHub Release for the tag.
   - Uploads the AAB to the Play Console internal testing track via
     `fastlane play_upload` as a **draft** (testers are not
     auto-notified).
5. **You** open the Play Console, verify the AAB on the internal track,
   and click **Promote release → Production** when ready.

That's the whole flow. There is no manual version bump, no manual tag,
no manual upload.

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

| Secret                  | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `RELEASE_PLEASE_TOKEN`  | PAT with `repo` (or fine-grained `contents:write` & `pull-requests:write`). **Required**: Tags created using GitHub's built-in `GITHUB_TOKEN` are suppressed by GitHub Actions and will never trigger the downstream `release.yml` workflow. A PAT is required for automated deployment. |
| `ANDROID_KEYSTORE_BASE64` | `base64` of the CI **upload** keystore (`~/.keystores/my-key.keystore` on this machine). |
| `KEY_ALIAS`             | Alias of the upload key inside the keystore.                            |
| `KEY_PASSWORD`          | Password for the upload key.                                            |
| `STORE_PASSWORD`        | Password for the keystore file itself.                                  |
| `PLAY_SUPPLY_JSON_KEY`  | Contents of the Play Console service-account JSON (release-manager).    |
| `GOOGLE_SERVICES_JSON`  | Contents of `android/app/google-services.json`. The Google Services Gradle plugin requires this at build time; mounted from this secret at workflow runtime, never logged. |

> **Important:** `RELEASE_PLEASE_TOKEN` is mandatory for end-to-end automation. While `GITHUB_TOKEN`
> has permission to create tags, GitHub's recursion prevention prevents tags created by `GITHUB_TOKEN`
> from firing downstream `on: push: tags` workflows. Always keep `RELEASE_PLEASE_TOKEN` set.

All seven secrets were seeded via `gh secret set` from the same local
sources the attd pipeline uses (shared upload keystore + Play Console
service account). The service account is linked to the Play developer
account that owns both apps, so a single JSON key covers both.

Play App Signing is enabled on this app. The CI signs AABs with the
**upload key** (the same `my-key.keystore` local builds sign with, and
the key registered on the Play Console); Google's app-signing key is
what the Play Store actually serves to users.

If the keystore or credentials ever need re-provisioning:

```bash
base64 -i ~/.keystores/my-key.keystore | tr -d '\n' | \
  gh secret set ANDROID_KEYSTORE_BASE64 --repo Shir0o/bible-read
gh secret set KEY_ALIAS --repo Shir0o/bible-read --body "my-key-alias"
gh secret set KEY_PASSWORD --repo Shir0o/bible-read --body "<your-key-password>"
gh secret set STORE_PASSWORD --repo Shir0o/bible-read --body "<your-store-password>"
gh secret set PLAY_SUPPLY_JSON_KEY --repo Shir0o/bible-read < ~/release-please-supply-key.json
gh secret set GOOGLE_SERVICES_JSON --repo Shir0o/bible-read < android/app/google-services.json
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
