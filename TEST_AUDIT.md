# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `test/widgets/responsive_scaffold_test.dart` | **Shallow & Brittle** | The test focuses entirely on `AnimatedScale` values (implementation detail) rather than verifying the responsive behavior (switching between `NavigationRail` and `NavigationBar`). It hardcodes screen size to a narrow width, missing the wide layout scenario entirely. |
| `test/services/reference_parser_test.dart` | **Shallow** | While `parseChaptersList` is tested, `normalizeOne` edge cases (like chapter clamping or invalid book names) are not explicitly tested in isolation, relying on the parser wrapper. |
| `test/services/group_service_test.dart` | **Incomplete Error Handling** | The service uses `_safeLog` to swallow errors. Tests verify that errors are logged (via `MockCrashlytics`), but they don't verify that the application remains in a consistent state or that specific critical failures propagate where necessary. |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **GroupService: Daily Progress Calculation** | `memberDailyCompletion` stream for a date with 2 scheduled chapters. User A has checked 1 item. User B has checked 2 items. | Stream emits `GroupMemberProgressData` for User A with `completion: 0.5` and User B with `completion: 1.0`. |
| **GroupService: Missing User Data** | `memberDailyCompletion` where a member UID exists in the members collection but has no document in the `users` collection. | Service should fall back to using the UID or a placeholder as the name, instead of crashing or hanging. |
| **ReferenceParser: Next Chapter Logic** | `ReferenceParser.nextChapter('Genesis 50')`. | Returns `'Exodus 1'`. |
| **ReferenceParser: Next Chapter End of Bible** | `ReferenceParser.nextChapter('Revelation 22')`. | Returns `null`. |
| **StatusRefreshIndicator: Custom Refresh** | Trigger refresh gesture on the widget. | Verify `onRefresh` callback is invoked and loading state is displayed. |
