# Test Stress Audit & QA Report

## 1. Test Integrity Audit

### Shallow Assertions & Brittle Tests
*   **`test/services/group_service_test.dart`**:
    *   **Issue:** Tests like `memberNames streams display names` and `schedule streams list of entries` use `stream.first`. This assumes the stream emits the correct data immediately as its first event. In real scenarios (or even complex mock scenarios), streams might emit an initial empty state or loading state.
    *   **Risk:** Tests are flaky or false positives if the stream emits an initial default value before the actual data.
*   **`test/pages/groups_page_test.dart`**:
    *   **Issue:** The test `lists all groups from service` relies on the `GroupsView` fallback logic (adding owner +1) to assert `'1 member'` for a malformed group. While valid as a regression test, it conflates "standard behavior" with "corruption recovery" without explicit separation.

### Architectural Test Debt
*   **`lib/widgets/views/groups_view.dart`**:
    *   **Issue:** **N+1 Query Problem**. The view subscribes to the `members` subcollection for *every* group in the list to calculate the "live" member count.
    *   **Risk:** This is a performance bottleneck. Tests using `pumpAndSettle` might hang or time out if the number of groups increases, as it waits for all these streams to settle.

## 2. Gap Analysis

### Edge Cases
*   **`ReferenceParser` (Ambiguity):** Input like `"Gen 1-2-3"` is parsed as `"Gen 1"` to `"Gen 3"` (ignoring the middle `2`). This behavior is implicit and untested.
*   **`GroupService` (Validation):** `createGroup` accepts any string for `name`, including empty strings (if bypassed by UI) or extremely long strings, which might fail in Firestore or UI rendering.

### Logic Branches
*   **`GroupsView` (Corruption Recovery):** The logic `final adjusted = hasOwner ? liveCount : liveCount + 1` is critical for self-healing group counts but lacks a dedicated, named test case ensuring it *only* activates when necessary.

## 3. Proposed New Tests

| Priority | Component | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **High** | `GroupService` | Stream Consistency | `memberNames` | Stream emits correct list eventually using `emitsThrough`, robust to initial empty states. |
| **Medium** | `ReferenceParser` | Ambiguous Range | `"Gen 1-2-3"` | Parses deterministically (e.g., `Gen 1`..`Gen 3` or invalid). |
| **Medium** | `GroupService` | Input Validation | `createGroup(name: "")` | Throws `ArgumentError` or similar (requires code change). |
| **Low** | `GroupsView` | Performance | List with 100 groups | Renders without crashing or timing out (verifies N+1 impact). |
