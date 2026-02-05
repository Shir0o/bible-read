# Stress Audit Report

## 1. Test Debt Summary

### Heavy Mocking & Brittleness
- **Risk**: Moderate
- **Location**: `test/services/group_service_test.dart`
- **Details**: The error handling tests rely on deep mocking of Firestore internals (`MockCollectionReference`, `MockDocumentReference`, etc.). This makes the tests brittle to changes in the Firestore SDK or internal implementation details.
- **Recommendation**: Refactor to use a wrapper around Firestore or accept that these tests are integration-heavy and might need maintenance.

### Shallow Assertions
- **Risk**: Low to Moderate
- **Location**: `test/widgets/group_card_test.dart`
- **Details**: The test verifies that "35%" is displayed, which implicitly tests the average calculation logic within the UI widget. While this works, it entangles UI testing with business logic validation. If the calculation logic changes or becomes more complex, the UI test might fail confusingly.
- **Recommendation**: Isolate logic testing in model/service tests and have the widget test verify that it displays what it is given (if possible) or clearly document the dependency.

### Missing Negative Testing
- **Risk**: High
- **Location**: `test/pages/login_page_test.dart`
- **Details**: Existing tests cover the "happy path" (successful login) and a generic "failure" path. They do not verify:
    -   Empty input fields.
    -   Invalid email formats.
    -   Specific error messages for different failure modes.
- **Recommendation**: Expand test coverage to include these negative scenarios.

## 2. Gap Analysis

### Input Validation
- **Scenario**: User enters an invalid email address (e.g., "plainaddress").
- **Current Behavior**: The app attempts to send this to Firebase Auth, which likely rejects it, but the UI feedback is a generic "Failed to sign in" or similar, rather than a proactive validation error.
- **Missing Code**: `LoginPage` lacks local validation logic.

### Edge Cases
- **Scenario**: `ReferenceParser` handling of "Chapter 0".
- **Current Behavior**: Returns raw input "Gen 0" instead of flagging it as invalid or normalizing it to a safe default.
- **Missing Test**: No test case specifically targets this edge behavior in `ReferenceParser`.

### Partial Failures
- **Scenario**: `GroupService.deleteGroup` failing halfway through deleting subcollections.
- **Current Behavior**: The operation might leave orphaned documents if a delete fails.
- **Missing Test**: No simulation of partial failure.

## 3. Proposed New Tests

| Priority | Component | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- | :--- |
| **High** | `LoginPage` | Input Validation | Empty email/password | SnackBar: "Please fill in all fields" |
| **High** | `LoginPage` | Input Validation | Invalid email format | SnackBar: "Please enter a valid email address" |
| **Medium** | `GroupService` | Partial Failure | `deleteGroup` throws on subcollection | Error logged, potentially cleanup triggered |
| **Low** | `ReferenceParser` | Invalid Chapter | "Gen 0" | Returns safe default or error indication |
