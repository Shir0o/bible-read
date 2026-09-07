# ADR 0002: Automated Play Store release notes prefill

- Status: Accepted
- Date: 2026-09-06
- Mirrors: [`Shir0o/attd` ADR 0002](https://github.com/Shir0o/attd/blob/main/docs/adr/0002-play-store-release-notes-prefill.md)

## Context

With ADR 0001, releasing to Google Play Store internal testing track was automated via `release-please` and `fastlane supply`. However, release notes in the Play Console draft releases remained empty because `fastlane supply` had `skip_upload_metadata: true`, requiring maintainers to manually copy-paste release notes or promote releases with blank tester notes.

Google Play Console enforces a strict 500-character limit per changelog locale, and raw `CHANGELOG.md` output contains Markdown links (`[#123](...)`), commit hashes (`([abc](...))`), and markdown headings that look broken or consume excessive characters.

## Decision

We automate release notes generation for Google Play Store internal testing releases by:

1. **Extracting the relevant release section from `CHANGELOG.md`** during the CI release workflow (`.github/workflows/release.yml`) matching the release tag's semver.
2. **Sanitizing the text**:
   - Stripping Markdown links to issues and commit hashes.
   - Stripping bold and italic formatting (`**`, `*`).
   - Normalizing list bullets to unicode bullet points (`• `).
   - Transforming section headings (e.g. `### Features`) to plain labels (`Features:`).
   - Clamping the text to <= 500 characters with ellipsis (`...`) if the release entry is unusually long, and providing a clean default (`Bug fixes and improvements.`) if empty.
3. **Placing the result in fastlane supply's canonical changelog path**:
   `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`, where `<versionCode>` is the derived versionCode for the release.
4. **Configuring Fastlane supply**:
   - Setting `skip_upload_metadata: false` and `skip_upload_changelogs: false`.
   - Setting `metadata_path: "fastlane/metadata/android"`.
   - Keeping `skip_upload_images: true` and `skip_upload_screenshots: true` so only text metadata and changelogs are synchronized.

## Consequences

### Positive

- Play Console internal testing drafts automatically populate release notes for testers without manual intervention.
- Formatted notes fit cleanly within Play Store's 500-character constraint.
- Zero external dependencies: parsed with Ruby, which is already present in the runner for Fastlane.

### Negative

- Releases with more than 500 characters of notes will be truncated with an ellipsis in Play Console (though the full changelog remains intact in GitHub Releases and `CHANGELOG.md`).
- Multi-locale Play Store descriptions require future expansion if non-English metadata is localized in the future.

## References

- ADR 0001: [`docs/adr/0001-release-automation.md`](./0001-release-automation.md)
- Fastlane supply docs: <https://docs.fastlane.tools/actions/supply/>
- Organization standard: `Shir0o/.github/docs/standards/play-store-release-pipeline.md`
