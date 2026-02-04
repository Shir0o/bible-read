# Test Integrity Audit & Gap Analysis

## 1. Test Debt Summary

### Duplicated Logic
- **Risk**: Moderate
- **Location**: `GroupService`
- **Details**: Name resolution logic (choosing between `name`, `displayName`, and `email`) is duplicated in `createGroup` and `_fetchUserInfos`. `memberNames` uses a simplified version that only checks `name`, leading to inconsistencies.
- **Impact**: Changes to name display logic must be applied in 3 places.

### Heavy Mocking
- **Risk**: Low
- **Location**: `test/services/group_service_test.dart` (Error Handling group)
- **Details**: The error handling tests use verbose `Mockito` setups to simulate Firestore exceptions. While necessary for coverage, they are brittle to API changes in the underlying Firestore library.

### Silent Failures
- **Risk**: High
- **Location**: `GroupService.deleteGroup`
- **Details**: The method swallows exceptions when deleting subcollection documents. If a deletion fails (e.g., due to permissions), the group document is still deleted, leaving orphaned subcollection data.
- **Remediation**: Tests should verify that partial failures are at least logged or handled more robustly.

### Shallow Assertions (ReferenceParser)
- **Risk**: Low
- **Location**: `ReferenceParser`
- **Details**: `normalizeOne` returns the raw input for chapter 0 (e.g., "Gen 0"), which is technically invalid but preserved. This might be a design choice but warrants review.

## 2. Gap Analysis

### Inconsistent User Name Display
- **Scenario**: A user signs up with Google and has a `displayName` but no `name` field in their `users` document.
- **Current Behavior**:
    -   `memberNames` stream: Ignores the user (returns nothing).
    -   `memberDailyCompletion` stream: correctly falls back to `displayName`.
- **Expected Behavior**: `memberNames` should also fall back to `displayName` and `email`.

### Partial Delete Failure
- **Scenario**: `deleteGroup` encounters an error deleting a member document.
- **Current Behavior**: The error is caught and ignored; the function proceeds to delete the group.
- **Missing Test**: No test simulates this partial failure state to verify data integrity or logging.

## 3. Proposed New Tests

| Priority | Component | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **High** | `GroupService` | Member name fallback | User with only `displayName` | `memberNames` returns `displayName` |
| **Medium** | `GroupService` | Partial delete failure | `delete()` throws on subcollection item | Error logged, group deleted (or transaction aborted) |
| **Low** | `ReferenceParser` | Invalid chapter 0 | "Gen 0" | Returns `null` or formatted error (instead of raw string) |
