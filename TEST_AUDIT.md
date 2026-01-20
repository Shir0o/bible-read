# Stress Audit Report

## 1. Test Integrity Audit (Test Debt)

| Issue Type | File | Test Case | Description |
| :--- | :--- | :--- | :--- |
| **Tautological Test** | `test/services/group_service_test.dart` | `approveJoinRequest performs batched write` | The test mocks `FirebaseFirestore`, `WriteBatch`, and `DocumentReference` to verify that `batch.commit()` is called. This tests the mock configuration rather than the code's behavior. It duplicates the coverage of `approveJoinRequest moves member and removes request` which verifies the actual outcome using `FakeFirebaseFirestore`. |
| **Logic/Test Mismatch** | `test/pages/groups_page_test.dart` | `lists all groups from service` | The test asserts that a group with `memberCount: 0` displays "1 member". This relies on `GroupsView` logic that artificially increments the count if the owner is missing from the members collection. While this might be intended behavior, the test blindly accepts this potential data inconsistency instead of verifying the `Group` model or Service handles it correctly. |
| **Shallow Assertion** | `test/models/group_test.dart` | `toFirestore outputs expected map` | The test checks if the output map matches a hardcoded map. It does not verify if this map structure adheres to what Firestore actually requires (e.g., if field names change in the future, this test needs manual update). |

## 2. Gap Analysis (Proposed New Tests)

| Priority | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Critical** | `GroupService.createGroup` name fallback | User with `name: null`, `displayName: 'DN'`, `email: 'e@mail.com'` | The created member record should use 'DN'. If 'DN' is null, it should parse the email username. |
| **High** | `GroupService.leaveGroup` cleanup | User leaves a group where they have progress entries | The `leaveGroup` method should attempt to delete the user's progress entries from `progress` and `progressSummary` subcollections. |
| **Medium** | `Group` model equality | Two `Group` instances with identical fields | `group1 == group2` should be true. Currently, the model uses identity equality. |
| **Low** | `GroupsView` error handling | Stream error from `allGroups` | The UI should show a "Failed to load groups" message or retry button. |

## 3. Recommended Actions

1.  **Refactor**: Remove the tautological `approveJoinRequest performs batched write` test. The outcome-based test `approveJoinRequest moves member and removes request` is sufficient and more robust.
2.  **New Test**: Add a test for `GroupService.createGroup` to verify the name selection logic (User Name > Display Name > Email Username).
3.  **New Test**: Add a test for `GroupService.leaveGroup` to verify that progress entries are cleaned up.
