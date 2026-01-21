# Stress Audit Report

## Objective 1: Test Integrity Audit

### Shallow Assertions
*   **Location**: `test/models/group_test.dart`
*   **Issue**: Tests verify object state by checking individual fields (e.g., `expect(group.name, 'Test')`). This is prone to error if new fields are added and not checked, or if the internal representation changes.
*   **Impact**: Tests might pass even if the object state is partially incorrect (e.g., `memberCount` defaulting wrong but not checked in some tests).

### Mocks & Isolation
*   **Location**: `test/services/group_service_test.dart`
*   **Issue**: While `FakeFirebaseFirestore` is generally used well, error handling tests (e.g., `groupsForUser logs and returns empty list on stream error`) switch to Mockito (`MockFirebaseFirestore`) to simulate stream errors.
*   **Impact**: This creates a disconnect between the "happy path" (fake) and "error path" (mock) tests. The mock configuration might not perfectly reflect how the real SDK or even the Fake SDK behaves, potentially leading to tautological tests.

### Brittleness
*   **Location**: `test/widgets/group_members_section_test.dart`
*   **Issue**: Relies on specific text finding (`find.text('Alice')`).
*   **Impact**: If the display logic changes (e.g., name truncation as mentioned in project memory, or adding badges), these tests will break even if the core logic is correct.
*   **Location**: `test/services/reference_parser_test.dart`
*   **Issue**: Relies on `ReferenceParser.normalizeOne(invalid)` in the expectation.
*   **Impact**: If `normalizeOne` is buggy, the test `falls back to normalizeOne for invalid inputs` will still pass. It validates the implementation against itself rather than against a fixed truth.

### Flakiness Risk
*   **Location**: `test/widgets/login_form_test.dart`
*   **Issue**: The test `logs error and shows snackbar when sign in fails` is currently `skip: true`.
*   **Impact**: Skipped tests represent dead code and unchecked functionality (technical debt).

## Objective 2: Gap Analysis

### Edge Cases
*   **Scenario**: Cross-book ranges in `ReferenceParser`.
*   **Missing Test**: Inputs like "Genesis 50 - Exodus 2" invoke complex logic in `_expandRange` that is not explicitly covered by existing tests.
*   **Scenario**: `Group` model validation.
*   **Missing Test**: The model lacks equality operators, making it hard to test for strict equality in collections or state updates.

### Negative Testing
*   **Scenario**: `GroupService` invalid inputs.
*   **Missing Test**: What happens if `createGroup` is called with empty strings? Current tests only check happy paths or Firestore errors, not business logic validation (if any exists).

### Logic Branches
*   **Scenario**: `ReferenceParser` range expansion logic.
*   **Missing Test**: The `_expandRange` function has loops and conditionals for handling start/end books and chapters. This complex logic is only partially exercised by intra-book ranges (e.g., "John 3-5").

## Test Debt Summary

The codebase has good coverage but suffers from shallow assertions in data models and potential brittleness in string parsing tests. The most significant technical debt is the lack of value equality in the `Group` model, which forces verbose and fragile field-by-field assertions. Additionally, the `ReferenceParser` has complex logic for range expansion that is not fully stress-tested against cross-book scenarios.

## Proposed New Tests

| Priority | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **High** | `ReferenceParser` Cross-Book Range | `"Genesis 50 - Exodus 2"` | `["Genesis 50", "Exodus 1", "Exodus 2"]` |
| **High** | `Group` Model Equality | `Group(id: '1', ...)` vs `Group(id: '1', ...)` | `group1 == group2` is `true` |
| Medium | `ReferenceParser` Partial Range | `"Genesis 50 - 2"` (Ambiguous) | Should probably parse as `Genesis 50`, `Genesis 2`? Or range? Logic needs verification. |
| Medium | `GroupService` Join Non-existent Group | `joinGroup('bad-id', ...)` | Should throw explicit error or return false. |
| Low | `LoginForm` Error Handling | Sign-in fails | Un-skip and fix the flakey test. |
