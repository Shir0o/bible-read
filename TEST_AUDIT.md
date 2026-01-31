# Test Stress Audit & QA Report

## 1. Test Integrity Audit

### Shallow Assertions
*   **`test/services/group_service_test.dart`**:
    *   **Issue:** The test `createGroup creates group and owner member` checks for the existence of specific fields (`name`, `ownerUid`, `memberCount`) but does not assert the *absence* of unexpected fields or strictly validate the document structure. This allows "data pollution" (unexpected fields) to go unnoticed.
    *   **Remediation:** Refactor to use deep map equality checks against the entire document data.

### Mocks & Isolation
*   **`test/services/group_service_test.dart` (Error Handling)**:
    *   **Issue:** The "Error Handling" group heavily relies on `MockFirebaseFirestore` and mocks internal method chains (e.g., `collection().doc().set()`). This makes the tests "tautological" (testing the mock setup) and brittle to implementation changes (e.g., adding `orderBy` or changing a query).
    *   **Risk:** Refactoring the service implementation will likely break these tests even if the logic remains correct.

### Flakiness Risk
*   **Stream Tests**: Tests like `memberNames streams display names` use `expectLater` with `emitsThrough`, which is good, but some older tests or potential future tests might rely on `stream.first`. The audit confirms `emitsThrough` is largely used, which mitigates this, but vigilance is required.

## 2. Gap Analysis

### Edge Cases & Input Validation
*   **`GroupService.createGroup`**:
    *   **Issue:** The method accepts any string for `name` and writes it to Firestore.
    *   **Scenario:** Passing an empty string `""` or whitespace `"   "`.
    *   **Outcome:** Creates a group with an invisible name. This causes UI issues and data integrity problems.
    *   **Missing Test:** Ensure `createGroup` throws `ArgumentError` for invalid names.
*   **`ReferenceParser`**:
    *   **Issue:** Ambiguous ranges like `"Gen 1-2-3"`.
    *   **Outcome:** Parsed as range `Gen 1` to `Gen 3`, skipping `2`. This is implicit behavior that might confuse users expecting a list `1, 2, 3`.

### Logic Branches
*   **`GroupService._ensureMemberCount`**:
    *   **Issue:** This private method is called in `approveJoinRequest` and `leaveGroup`. It performs a self-healing fix if `memberCount` is missing.
    *   **Coverage:** While covered implicitly by "seeds memberCount when missing" tests, it lacks explicit isolation to ensure it handles race conditions or partial failures (though difficult to test without extensive mocking).

### Architectural Test Debt
*   **`GroupsView`**:
    *   **Issue:** N+1 Query Problem (subscribing to `members` for every group).
    *   **Risk:** Performance degradation not captured by current widget tests which often use small datasets.

## 3. Proposed New Tests

| Priority | Component | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **High** | `GroupService` | Input Validation | `createGroup(name: "")` | Throws `ArgumentError`. |
| **High** | `GroupService` | Input Validation | `createGroup(name: "   ")` | Throws `ArgumentError`. |
| **Medium** | `GroupService` | Input Validation | `joinGroup(name: "")` | Throws `ArgumentError`. |
| **Medium** | `ReferenceParser` | Ambiguity | `"Gen 1-2-3"` | Verification of current behavior (range expansion) to prevent regression or decide on change. |
| **Low** | `GroupsView` | Performance | List of 100 groups | Benchmark test (integration) to measure frame build time. |
