# Test Stress Audit & QA Report

## 1. Test Integrity Audit

### Shallow Assertions
*   **`test/pages/groups_page_test.dart`**: The test `lists all groups from service` asserts `'1 member'` for a group (`g2`) that is explicitly seeded with `memberCount: 0` and no sub-members.
    *   *Issue:* The test relies on the view's fallback logic (adding +1 for the owner if missing) rather than testing the standard data flow. This masks potential issues in `memberCount` synchronization.
*   **`test/services/group_service_test.dart`**: Tests like `groupsForUser streams groups` use `.firstWhere((g) => g.isNotEmpty)`.
    *   *Issue:* This skips any initial empty emissions (common with Firestore streams). If the application introduces a regression causing a permanent empty state or a flash of missing content, this test might still pass or flake, rather than failing deterministically.

### Mocks & Isolation
*   **`test/services/group_service_test.dart`**: Heavily mixes `FakeFirebaseFirestore` (excellent for logic) with `MockFirebaseFirestore` (brittle, used for error injection).
    *   *Risk:* Tests using `MockFirebaseFirestore` rely on internal implementation details (e.g., `collection()`, `doc()`, `snapshots()`) matching exactly. If the implementation changes (e.g., adding a `orderBy`), the mock configuration breaks even if logic is correct.
*   **`test/pages/groups_page_test.dart`**: Uses `RecordingGroupService` (partial mock). This is generally a good pattern but limits the ability to test integration with the real Firestore logic in the UI.

### Flakiness Risk
*   **`test/pages/groups_page_test.dart`**: Uses `tester.pumpAndSettle()`. The `GroupsView` uses a `SkeletonLoader` which implements a minimum 500ms timer.
    *   *Risk:* `pumpAndSettle` waits for all timers. If the `SkeletonLoader` timer logic changes (e.g., to periodic), the test will hang. It also makes the test suite slower (500ms per pump).

## 2. Gap Analysis

### Edge Cases
*   **`ReferenceParser` (Logic):** The parser clamps out-of-range chapters (e.g., "Genesis 100" -> "Genesis 50") but there is no explicit test case verifying this behavior.
*   **`GroupService` (Boundaries):** No tests for `createGroup` with extremely long names or invalid characters (though Firestore handles most, validation should ideally happen in the service).
*   **`GroupService` (Concurrency):** Race conditions when multiple users join/leave simultaneously are not tested (hard to test, but a gap).

### Logic Branches
*   **`GroupsView` (Display Logic):** The logic `final adjusted = hasOwner ? liveCount : liveCount + 1` handles data corruption (missing owner doc). This branch is triggered in existing tests, but not explicitly identified as a "Corruption Recovery" test case.
*   **`ReferenceParser.parseChaptersList`**: The logic that inherits the book from the previous entry (e.g., "John 3, 4") is complex and might fail on boundary switches (e.g., "Jude 1, 2" where 2 is invalid).

## 3. Proposed New Tests

| Priority | Component | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **High** | `ReferenceParser` | Out-of-range chapter | `"Genesis 100"` | Returns `"Genesis 50"` (Clamped) or `null` (Invalid) depending on spec. |
| **High** | `GroupService` | Stream Consistency | `groupsForUser` | Stream emits correct list immediately without intermediate empty states. |
| **Medium** | `GroupsView` | Skeleton Loading | Load Delay | Skeleton displays for min 500ms, then content appears. |
| **Medium** | `GroupService` | Invalid Auth | `deleteGroup` with wrong `ownerUid` | Throws `StateError`. (Already covered, but could be expanded to other methods). |
| **Low** | `ReferenceParser` | Invalid Range Syntax | `"Gen 1-2-3"` | Parses as `Gen 1`, `Gen 2` (ignoring 3) or safe fallback. |
