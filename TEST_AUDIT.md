# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt Summary

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `lib/services/group_service.dart` | **Critical Coverage Gap** | Methods `recalcProgressForUserInGroup` and `fixMemberProgressSummariesForUser` are completely untested. These handle data consistency and aggregation, making them high-risk for regressions. |
| `test/services/group_service_test.dart` | **Inconsistent Mocking Strategy** | Error scenarios rely on `MockFirebaseFirestore` (Mockito) while happy paths use `FakeFirebaseFirestore`. This hybrid approach increases maintenance burden and brittleness. |
| `test/widgets/responsive_scaffold_test.dart` | **Shallow Assertions** | Tests confirm widget presence (`findsOneWidget`) but fail to verify layout constraints, property updates, or that the `PageView` content effectively changes beyond the index state. |
| `test/widgets/status_refresh_indicator_test.dart` | **Brittleness** | Tests likely rely on timing matches with internal animation durations, which is a common source of flakiness in widget tests involving animations. |

## Objective 2: Gap Analysis

### Proposed New Tests

| Priority | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **High** | **Recalc Progress (Basic)** | Group with progress entries across multiple dates. | `recalcProgressForUserInGroup` sums all item counts and updates `progressSummary/.../completed`. |
| **High** | **Recalc Progress (Backfill)** | Entry exists but `count` field is missing. | `recalcProgressForUserInGroup` counts the items in the subcollection and writes the `count` field to the entry document. |
| **Medium** | **Fix Summaries (Iteration)** | User belongs to multiple groups. | `fixMemberProgressSummariesForUser` iterates through all user groups and triggers a recalc for each. |
| **Medium** | **Recalc Permissions** | Non-member (not owner) attempts recalc. | Method returns early without modifying data (idempotent/safe). |
| **Low** | **Responsive Layout Switch** | Screen width changes from 400 to 800. | Widget rebuilds, switching from `NavigationBar` to `NavigationRail`. |
