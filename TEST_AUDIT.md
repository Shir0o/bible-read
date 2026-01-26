# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `lib/services/group_service.dart` | **Critical Coverage Gap** | Core business logic for `memberOverallCompletion`, `recalcProgressForUserInGroup`, and `fixMemberProgressSummariesForUser` is completely untested. These methods contain complex aggregation logic that is prone to regression. |
| `test/services/group_service_test.dart` | **Over-Mocking** | Error handling tests rely heavily on `MockFirebaseFirestore` and `when(...).thenThrow(...)` chains. This makes the tests brittle and tautological (verifying the mock throws and catch block runs, rather than verifying system state). Happy path tests use `FakeFirebaseFirestore` which is good, but the mix creates inconsistency. |
| `test/widgets/status_refresh_indicator_test.dart` | **Brittleness** | Tests rely on hardcoded `pump` durations (e.g., `350ms`, `1s`, `2s`) that match the implementation's internal animation times. Changing the animation speed in the widget would silently break the tests or cause timeouts. |
| `lib/widgets/responsive_scaffold.dart` | **Shallow Assertions** | `responsive_scaffold_test.dart` verifies widget presence (`findsOneWidget`) but does not deeply verify layout properties (e.g., that the body is actually visible or constraints are applied). |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **ReferenceParser: Verse-Only Shorthand** | Input `John 3, 4`. | Current behavior: `['John 3', '4']`. Desired behavior (Feature Gap): `['John 3', 'John 4']`. Existing parser fails to carry over book context for simple comma-separated lists. |
| **GroupService: Member Overall Completion** | Group with schedule (2 chapters) and member entries (1 chapter completed). | Stream emits list: [Member: 50%]. |
| **GroupService: Recalc Progress** | User has progress scattered across dates but summary is missing/wrong. | `recalcProgressForUserInGroup` sums up all entries and updates `progressSummary/data/entries/{uid}` with correct total. |
| **ReferenceParser: Complex Range Context** | Input `Gen 1-3, 5`. | Expected: `['Genesis 1', 'Genesis 2', 'Genesis 3', 'Genesis 5']`. |
