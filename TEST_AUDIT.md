# Test Audit Report

## Objective 1: Test Integrity Audit

### Shallow Assertions
*   **`GroupService` - `joinGroup` Test**: The test `joinGroup creates join request and notification` checks for the existence of a notification but fails to verify critical fields like `groupId`, `message` content, and `timestamp`. It also doesn't verify that *only* the owner receives the notification.
*   **`GroupService` - `memberDailyCompletion` Test**: The test verifies the calculated percentage but does not simulate partial failures (e.g., if one subcollection read fails) to ensure the system degrades gracefully as per the `try-catch` blocks in the source code.

### Mocks & Isolation
*   **Good Usage**: The project makes excellent use of `FakeFirebaseFirestore` for most tests, allowing for realistic state transitions without tautological mocking.
*   **Necessary Mocking**: `FirebaseCrashlytics` is mocked to prevent errors, which is appropriate.
*   **Appropriate Mocking**: The "Error Handling" group correctly uses `MockFirebaseFirestore` to simulate Firestore exceptions, which `FakeFirebaseFirestore` cannot easily do.

### Brittleness
*   **Time Dependence**: `GroupService.fetchTodaysChapters` relies on `DateTime.now()` and constructs a date ID based on the local time of the execution environment. This could lead to flaky tests if run near midnight or in different timezones (CI vs Local).
*   **Hardcoded Dates**: Some tests use `DateTime.now()` mixed with hardcoded date strings, which requires careful synchronization.

### Flakiness Risk
*   **Async Streams**: Tests for `memberDailyCompletion` and `memberOverallCompletion` rely on `Stream.multi` and multiple async Firestore queries. While `expectLater` is used effectively, the complexity of the stream logic (handling missing members, denied progress permissions) creates a risk of race conditions where the stream might emit an initial empty state before the populated state, potentially causing test failures if not handled with `emitsThrough`.

## Objective 2: Gap Analysis

### Edge Cases
*   **Empty Inputs**: `createGroup` checks for empty names, but `requestJoin` does not validate `name` (though strictly less critical).
*   **Max Boundaries**: No tests for maximum number of members or maximum number of chapters in a schedule.
*   **Data Integrity**: `requestJoin` allows creating a join request for a non-existent group, leading to "orphan" subcollections in Firestore.

### Negative Testing
*   **Missing Group**: No test confirms that operations like `joinGroup`, `leaveGroup`, or `updateSchedule` fail appropriately when the `groupId` does not exist.
*   **Already Member**: No test checks the behavior when a user tries to join a group they are already in.
*   **Permission Denials**: While some error handling tests exist, there are no tests simulating Firestore permission denials (security rules) for specific subcollections (like `items` inside `entries`) to verify the "best-effort" logic in progress calculations.

### Logic Branches
*   **`requestJoin` Pre-check**: The code writes to the `joinRequests` collection *before* checking if the group exists or if the user is the owner. This is a logic flow that needs reversal and testing.
*   **`approveJoinRequest` Idempotency**: The code handles re-approving a member, but there is no explicit test verifying that `memberCount` is *not* incremented if the user is already a member.

## Proposed New Tests

| Priority | Feature | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **Critical** | `GroupService.joinGroup` | Join non-existent group | `groupId`: "invalid", `uid`: "user1" | Throw `StateError` or `Exception`. Do not write to Firestore. |
| High | `GroupService.joinGroup` | Join group as existing member | `groupId`: "g1", `uid`: "member1" | Throw `StateError` or handle gracefully without creating request. |
| Medium | `GroupService.createGroup` | Create group with duplicate name | `name`: "Existing Group" | Allow (if by design) or Warn. (Current logic allows duplicates). |
| Medium | `GroupService.updateSchedule` | Update with empty schedule | `schedule`: `GroupSchedule(chapters: [])` | Update successfully or Throw `ArgumentError`. |
| Low | `ReferenceParser` | Parse completely invalid string | `input`: "Hello World" | Return empty list or valid chunks only. |

## Remediation Plan (Automated)

**Selected "Test Debt"**: Refactor `joinGroup` test in `test/services/group_service_test.dart` to assert all notification fields.
**Selected "New Test"**: Implement logic and test for "Join non-existent group" in `GroupService`.

### Refactored Code
Update `test/services/group_service_test.dart` to verify `AppNotification` fields deeply.

### New Test Implementation
Add test `throws StateError when group does not exist` and update `GroupService.requestJoin` to fetch group doc before writing.
