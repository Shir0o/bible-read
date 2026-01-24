# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `test/services/reference_parser_test.dart` | **Shallow / Gap** | `parseChaptersList` is tested, but `nextChapter` is not tested at all. `normalizeOne` edge cases (like chapter clamping or invalid book names) are not explicitly tested in isolation, relying on implicit testing via the parser wrapper. |
| `test/services/group_service_test.dart` | **Incomplete Error Handling** | The service uses `_safeLog` to catch and log errors in streams. Tests verify that errors return empty lists (via mocks), but the swallowing of exceptions makes it difficult to verify that specific critical failures are propagated or handled beyond logging. |
| `lib/widgets/status_refresh_indicator.dart` | **Missing Tests** | No test file exists for this widget. Logic for pull-to-refresh animation, state transitions (loading/success/error), and timeout handling is untested. |
| `lib/services/book_achievement_refresher.dart` | **Missing Tests** | No test file exists. Business logic for unlocking book achievements based on aggregated chapter progress is untested. |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **ReferenceParser: Next Chapter Logic** | `ReferenceParser.nextChapter('Genesis 50')`. | Returns `'Exodus 1'` (cross-book boundary). |
| **ReferenceParser: Next Chapter End of Bible** | `ReferenceParser.nextChapter('Revelation 22')`. | Returns `null` (end of canon). |
| **ReferenceParser: Next Chapter Normalization** | `ReferenceParser.nextChapter('gen 1')`. | Returns `'Genesis 2'` (verifies input normalization). |
| **ReferenceParser: Normalize Clamping** | `ReferenceParser.normalizeOne('Genesis 100')`. | Returns `'Genesis 100'` (current behavior) or clamped value? *Audit reveals `normalizeOne` does NOT clamp, but `_parseEndpoint` does. Tests should verify intended behavior.* |
| **StatusRefreshIndicator: Custom Refresh** | Trigger refresh gesture on the widget. | Verify `onRefresh` callback is invoked and loading state is displayed. |
| **StatusRefreshIndicator: Success State** | Complete `onRefresh` successfully. | Verify 'Refreshed successfully' message and success color bar are displayed for a duration. |
| **StatusRefreshIndicator: Error State** | Throw exception in `onRefresh`. | Verify 'Refresh failed' message and error color bar are displayed for a duration. |
| **BookAchievementRefresher: Unlock Logic** | `refresh` called with all chapters of 'Ruth' completed. | Unlocks 'book_ruth' achievement via `AchievementService`. |
