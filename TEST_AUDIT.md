# Stress Audit Report

## 1. Test Integrity Audit

### Shallow Assertions
*   **GroupService Streams**: The tests for `groupsForUser`, `allGroups`, and `schedule` check that *something* is returned or that the list has the correct length, but they often lack deep inspection of the returned objects to ensure all fields (especially computed or complex ones) are correct.
*   **Data Integrity vs. Presence**: Many tests verify that a document "exists" after an operation (e.g., `createGroup`) but do not exhaustively verify all fields, such as `isPublic` or derived properties.

### Mocks & Isolation
*   **Tautological Testing in `approveJoinRequest`**: The test `approveJoinRequest performs batched write` in `test/services/group_service_test.dart` uses `MockFirebaseFirestore` and `MockWriteBatch`. It strictly verifies that specific methods were called on the mocks (`batch.set`, `batch.update`). This is brittle and tautological; it tests the implementation details (that a batch was used) rather than the outcome. If the implementation switched to a transaction or individual writes that achieved the same result, this test would fail despite the code working correctly. The `FakeFirebaseFirestore` tests are much higher value here.
*   **Manual Mocks in `LoginForm`**: `test/widgets/login_form_test.dart` uses manual classes `RecordingAuth` and `FailingAuth`. While functional, they don't simulate the full behavior of the Firebase Auth SDK (like diverse error codes) and are less flexible than a library like `mocktail` or `mockito`.

### Brittleness
*   **ReferenceParser Regex**: The `ReferenceParser` relies heavily on complex regular expressions. While necessary for the task, the lack of a comprehensive suite of "dirty" input tests makes it brittle to regressions if the regex is touched.
*   **UI Key Dependence**: `LoginForm` tests rely on `Key('loginEmailField')`. If these keys are removed or changed during a UI refactor, tests will break even if the user-facing functionality (finding by label) works.

### Flakiness Risk
*   **Skipped Tests**: The test `logs error and shows snackbar when sign in fails` in `login_form_test.dart` is explicitly skipped (`skip: true`). This indicates a known flakiness or failure that was ignored rather than fixed, leaving error handling logic unprotected.

## 2. Gap Analysis

### Edge Cases
*   **Bible Reference Clamping**: `ReferenceParser` logic clamps chapter numbers (e.g., if user types "Genesis 100", it might default to 50). This behavior is implemented but not explicitly tested.
*   **Cross-Book Ranges**: The parser logic handles `Gen 50 - Ex 2`, but there is no test case verifying this specific cross-book expansion works correctly.
*   **Fuzzy Matching**: The parser implements Levenshtein distance for book names (e.g., handling typos), but there are no visible tests verifying that "Gneesis" resolves to "Genesis".

### Negative Testing
*   **Group Deletion**: `GroupService.deleteGroup` performs a massive cascading delete (members, schedule, join requests, progress entries). There are **ZERO** tests for this method. If this fails, it leaves orphaned data.
*   **Failed Sign-In**: As noted, the test for failed sign-in is skipped.
*   **Empty Inputs**: `LoginForm` has logic to return early if fields are empty (`if (email.isEmpty || password.isEmpty) return;`), but there is no test verifying that the "Sign In" button does nothing in this state.

### Logic Branches
*   **Progress Recalculation**: `GroupService.recalcProgressForUserInGroup` contains complex logic to sum up progress from multiple documents and update a summary. This method has no corresponding tests.
*   **Complex Streams**: `memberDailyCompletion` and `memberOverallCompletion` in `GroupService` have intricate logic for combining streams (members + schedule + progress). These are critical for the app's dashboard but appear to have no direct unit tests covering the data combination logic.
*   **Side Effects**: `createGroup` attempts to copy the user's name to the member record ("best-effort"). This side effect is not verified in the `createGroup` tests.

## 3. Test Debt Summary

The codebase has good "happy path" coverage for basic CRUD operations using `FakeFirebaseFirestore`, which is a strong foundation. However, the most complex business logic (stats calculation, cascading deletes, parsing algorithms) is under-tested. The presence of skipped tests and missing scenarios for destructive actions (`deleteGroup`) represents a significant risk.

## 4. Proposed New Tests

| Feature | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **GroupService** | Cascading Delete | `deleteGroup(groupId, ownerUid)` | Group doc, members, schedule, requests, and all progress subcollections are deleted. |
| **GroupService** | Progress Recalculation | `recalcProgressForUserInGroup` with disparate daily entries | `progressSummary` document is updated with the correct sum of all daily counts. |
| **GroupService** | Daily Completion Stats | `memberDailyCompletion` stream with 1 user having 50% progress | Stream emits `GroupMemberProgressData` with `completion: 0.5`. |
| **ReferenceParser** | Cross-Book Range | `parseChaptersList("Gen 50 - Ex 2")` | Returns `['Genesis 50', 'Exodus 1', 'Exodus 2']`. |
| **ReferenceParser** | Chapter Clamping | `parseChaptersList("Genesis 100")` | Returns `['Genesis 50']` (or handles gracefully per spec). |
| **ReferenceParser** | Fuzzy Book Matching | `parseChaptersList("Gneesis 1")` | Returns `['Genesis 1']`. |
| **LoginForm** | Empty Submission | Tap "Sign In" with empty email/pass | `signInWithEmailAndPassword` is NOT called; no loading state. |
| **LoginForm** | Auth Failure | `auth.signIn` throws Exception | Error is logged to Crashlytics; SnackBar appears (Unskip existing test). |
| **GroupService** | Member Name Sync | `createGroup` where user has `displayName` | Created member record contains `name` matching the user's `displayName`. |
