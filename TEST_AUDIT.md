# Test Audit Report

## Objective 1: Test Integrity Audit

### Test Debt

| File | Issue Type | Description |
| :--- | :--- | :--- |
| `lib/services/group_service.dart` | **Critical Coverage Gap** | Core business logic for `memberOverallCompletion`, `recalcProgressForUserInGroup`, and `fixMemberProgressSummariesForUser` is completely untested. These methods contain complex aggregation logic that is prone to regression. |
| `test/services/group_service_test.dart` | **Over-Mocking & Inconsistency** | Error handling tests rely heavily on `MockFirebaseFirestore` and `when(...).thenThrow(...)` chains, making them brittle and tautological. Happy path tests use `FakeFirebaseFirestore`, creating inconsistency in testing strategy. |
| `test/widgets/status_refresh_indicator_test.dart` | **Brittleness** | Tests rely on matching internal animation durations. While they use constants, any change to the animation logic requires synchronized updates to tests to avoid timeouts. |
| `lib/widgets/responsive_scaffold.dart` | **Shallow Assertions** | `responsive_scaffold_test.dart` verifies widget presence (`findsOneWidget`) but does not deeply verify layout properties (e.g., that the body is correctly switched or constraints are applied). |

## Objective 2: Gap Analysis

### Proposed New Tests

| Scenario | Input | Expected Outcome |
| :--- | :--- | :--- |
| **GroupService: Member Overall Completion** | Group with schedule (2 chapters) and member entries (1 chapter completed). | Stream emits list: [Member: 50%]. Verifies calculation `completed / total_scheduled`. |
| **GroupService: Recalc Progress** | User has progress scattered across dates but summary is missing/wrong. | `recalcProgressForUserInGroup` sums up all entries from `progress/{date}/entries/{uid}` and updates `progressSummary/data/entries/{uid}` with correct total. |
| **GroupService: Fix Member Progress Summaries** | User belongs to multiple groups. | `fixMemberProgressSummariesForUser` iterates all groups and calls recalc for each. |
