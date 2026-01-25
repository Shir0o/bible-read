# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `lib/services/group_service.dart` | **Incomplete Error Handling** | The service uses `_safeLog` to catch and swallow errors in almost all methods. While this prevents crashes, the tests (in `group_service_test.dart`) only verify that `Crashlytics` records the error. They do not verify that the app state remains consistent or that the UI receives appropriate feedback (e.g., via return values or streams). |
| `test/services/group_service_test.dart` | **Over-Mocking** | Error handling tests heavily rely on `MockFirebaseFirestore`, `MockCollectionReference`, etc., making them brittle to implementation details (e.g., specific order of calls). |
| `lib/services/reference_parser.dart` | **Untested Logic** | The `nextChapter` and `chapterCount` methods are completely untested. `normalizeOne` has edge cases (invalid books, negative numbers) that are not explicitly covered by existing tests. |
| `test/widgets/responsive_scaffold_test.dart` | **Shallow Assertions** | (Previous audit note) *Re-evaluated*: Current tests seem to cover basic responsive behavior, but could be improved by verifying specific layout properties rather than just widget presence. |
| `lib/widgets/status_refresh_indicator.dart` | **No Coverage** | This custom widget has complex state logic (Idle -> Loading -> Success/Error) and animations, but currently has **zero** tests. |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **ReferenceParser: Next Chapter (Standard)** | `ReferenceParser.nextChapter('Genesis 1')` | Returns `'Genesis 2'` |
| **ReferenceParser: Next Chapter (Book Transition)** | `ReferenceParser.nextChapter('Genesis 50')` | Returns `'Exodus 1'` |
| **ReferenceParser: Next Chapter (End of Bible)** | `ReferenceParser.nextChapter('Revelation 22')` | Returns `null` |
| **ReferenceParser: Invalid Input** | `ReferenceParser.nextChapter('Invalid Book 1')` | Returns `null` |
| **StatusRefreshIndicator: Success Flow** | User pulls to refresh, action succeeds. | Widget shows "Refreshing...", then "Refreshed successfully", and progress bar turns green/tertiary. |
| **StatusRefreshIndicator: Error Flow** | User pulls to refresh, action throws error. | Widget shows "Refresh failed", progress bar turns red/error, and error state persists briefly. |
| **GroupService: Member Progress (Negative)** | `memberDailyCompletion` called when user has no permissions to read progress subcollection. | Stream should emit empty list or list with 0% completion, without crashing the app (swallowed error). |
