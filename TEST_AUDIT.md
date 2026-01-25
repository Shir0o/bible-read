# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `lib/services/group_service.dart` | **Critical Coverage Gap** | Core business logic for progress tracking (`memberDailyCompletion`, `memberOverallCompletion`, `recalcProgressForUserInGroup`) and data management (`deleteGroup`, `fixMemberProgressSummariesForUser`) is completely untested. These methods contain complex aggregation logic that is prone to regression. |
| `test/services/group_service_test.dart` | **Over-Mocking** | Error handling tests rely heavily on `MockFirebaseFirestore` and `when(...).thenThrow(...)` chains. This makes the tests brittle and tautological (verifying the mock throws and catch block runs, rather than verifying system state). Happy path tests use `FakeFirebaseFirestore` which is good, but the mix creates inconsistency. |
| `test/widgets/status_refresh_indicator_test.dart` | **Brittleness** | Tests rely on hardcoded `pump` durations (e.g., `10s`, `2s`) that match the implementation's internal animation times. Changing the animation speed in the widget would silently break the tests or cause timeouts. |
| `lib/widgets/responsive_scaffold.dart` | **Shallow Assertions** | `responsive_scaffold_test.dart` verifies widget presence (`findsOneWidget`) but does not deeply verify layout properties (e.g., that the body is actually visible or constraints are applied). |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **GroupService: Member Daily Completion** | Group with 2 members. Schedule has 2 chapters. Member A read 1 chapter. Member B read 2 chapters. | Stream emits list: [Member A: 50%, Member B: 100%]. |
| **GroupService: Member Daily Completion (No Entries)** | Group with 1 member. Schedule has 1 chapter. No progress entries exist. | Stream emits list: [Member: 0%]. Should not crash or return empty list (unless intended). |
| **GroupService: Delete Group** | Owner calls `deleteGroup`. Group has members, schedule, and progress subcollections. | All subcollections (members, schedule, progress) and the group document are deleted. |
| **GroupService: Delete Group (Not Owner)** | Non-owner calls `deleteGroup`. | Throws `StateError`. Group remains intact. |
| **ReferenceParser: Verse-Only Shorthand** | Input `John 3, 4`. | Current behavior: `['John 3', '4']`. Desired behavior (Feature Gap): `['John 3', 'John 4']` or validation error. Existing parser allows invalid `4`. |
