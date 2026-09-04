# ADR 0001: Android release automation pipeline

- Status: Accepted
- Date: 2026-09-03
- Mirrors: [`Shir0o/attd` ADR 0001](https://github.com/Shir0o/attd/blob/main/docs/adr/0001-release-automation.md)

## Context

Releasing was fully manual: the maintainer bumped `pubspec.yaml` by hand
(including the `+buildNumber`), built locally, uploaded to the Play
Console by hand, and cut loose tags (`1.18.0+19`, `1.19.0+20`) with no
CHANGELOG and no GitHub Releases. The sibling repo `attd` already solved
this; bible-read should behave identically so the release process is the
same across both apps.

## Decision

We adopt a release pipeline built from four pieces:

1. **release-please** as the single source of truth for versioning,
   CHANGELOG generation, tag pushing, and GitHub Release creation.
2. **fastlane supply** for Play Console uploads.
3. **Play App Signing** for keystore management — CI signs with the
   upload key, Google holds the app-signing key.
4. **Internal-track-first** delivery — automated uploads land on the
   internal testing track; production promotion stays a manual click.

Release-please reads **PR titles** (not commit messages) as the
conventional-commits signal; squashed merges onto `main` keep the PR
title as the merge commit subject. PR title lint enforces the format
on every opened/edited/synchronize PR event.

Deviations from attd's pipeline (kept minimal):

- No `ENV_SECRETS` secret: bible-read has no `.env`-driven assets and
  `lib/firebase_options.dart` is committed.
- The `+buildNumber` suffix in `pubspec.yaml` is retired by the first
  release-please bump; `versionCode` derives from the tag instead
  (`major*10000 + minor*100 + patch`), which is already past every
  legacy build number.

## Alternatives considered

See the attd ADR for the full comparison tables (release-please vs.
standard-version/semantic-release, fastlane supply vs. alternatives,
keystore strategies, promotion gating). The conclusions carry over
unchanged: release-please (Google-maintained, PR-title-driven, fits
squash-merge policy), fastlane supply (Google-recommended, retry +
release-status semantics), Play App Signing (already enrolled),
internal-track-first (fail-safe by default).

## Consequences

### Positive

- Releasing is one click after the conventional-commit PR merges.
- Version numbers, changelogs, tags, and Play Console uploads are
  consistent across releases — and identical to the attd flow.
- The upload keystore (`~/.keystores/my-key.keystore`) is shared with
  attd; one credential set, one rotation story.

### Negative

- Seven new GitHub secrets to provision and rotate. Documented in
  `RELEASING.md` but not auto-rotated.
- Conventional-commits discipline is now required on PR titles (was
  optional). PRs with freeform titles are rejected by `pr-title-lint`
  until retitled.
- The CI upload key, once enrolled on the Play Console, cannot be
  rotated without a Play Console "Upload key reset" ticket.
- Local `flutter run` loses the auto-incrementing `+buildNumber`;
  reinstall-downgrade needs a one-off uninstall or `--build-number`.

### Reversibility

- **Easy**: the PR title lint, the release-please config, the Fastfile,
  and the release-please bot workflow are all removable in one commit.
- **Medium**: the release.yml workflow is removable but leaves behind
  orphan tags/releases on GitHub.
- **Hard**: the Play App Signing enrollment is irreversible without a
  Play Console support ticket. Already paid (enrollment predates this
  ADR); this ADR records the choice but does not create the
  irreversibility.
- **Hardest**: the `RELEASE_PLEASE_TOKEN` PAT and the
  `PLAY_SUPPLY_JSON_KEY` service-account JSON, once issued, retain
  access to the repo and Play Console respectively until manually
  revoked. Rotate by deleting the secrets in GitHub settings.

## References

- release-please config: [`release-please-config.json`](../../release-please-config.json)
- Release workflow: [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
- Release-please bot: [`.github/workflows/release-please.yml`](../../.github/workflows/release-please.yml)
- PR title lint: [`.github/workflows/pr-title-lint.yml`](../../.github/workflows/pr-title-lint.yml)
- fastlane config: [`fastlane/Fastfile`](../../fastlane/Fastfile)
- Operate it: [`RELEASING.md`](../../RELEASING.md)
- attd counterpart: <https://github.com/Shir0o/attd/blob/main/docs/adr/0001-release-automation.md>
