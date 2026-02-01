# Stress Audit Report

## 1. Test Integrity Audit

### Shallow Assertions
- **File**: `test/services/group_service_test.dart`
- **Test**: `createGroup creates group and owner member`
- **Issue**: Only checks `memberCount` and existence. Does not verify `joinedAt` is a valid timestamp, nor that the group ID is non-empty.
- **File**: `test/models/group_test.dart`
- **Test**: `fromFirestore handles missing fields`
- **Issue**: Asserts that critical fields like `ownerUid` default to empty strings, masking potential data corruption issues.

### Mocks & Isolation
- **File**: `test/services/group_service_test.dart`
- **Issue**: Heavy use of `MockFirebaseFirestore` for error scenarios creates "tautological tests" that verify the mock setup rather than the service's reaction to real Firestore behavior.

### Brittleness
- **File**: `test/pages/login_page_test.dart`
- **Issue**: Uses `find.text('Login')` which will break if copy changes.
- **File**: `test/widgets/feed_card_ux_test.dart`
- **Issue**: `expect(textField.maxLines, inInclusiveRange(3, 5))` is loose and might miss unintended layout changes.

### Flakiness Risk
- **File**: `test/services/group_service_test.dart`
- **Issue**: Tests relying on `FieldValue.serverTimestamp()` are compared against `isA<Timestamp>()` rather than approximate time ranges.

## 2. Gap Analysis

### Edge Cases
- **Group Creation**: No test for group names containing only whitespace.
- **Group Leaving**: No test for what happens when the *owner* leaves the group. Current logic allows it, leaving the group "headless".

### Negative Testing
- **Login Failure**: `LoginPage` has zero coverage for failed login attempts (e.g., wrong password, network error).
- **Join Group**: No test for attempting to join a group one is already a member of.

### Logic Branches
- **GroupService**: `_ensureMemberCount` logic is only implicitly tested.
- **GroupService**: `fixMemberProgressSummariesForUser` error handling is swallow-only.

## 3. Proposed New Tests

| Priority | Scenario | Input | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **High** | Login Failure | Incorrect email/password | Show error snackbar/message "Failed to sign in. Please check credentials." |
| **High** | Owner Leaves Group | `leaveGroup` called by owner | Throw `StateError` or prevent action |
| **Medium** | Re-join Group | `joinGroup` by existing member | Throw error or return success without duplicate request |
| **Medium** | Empty Group Name | `createGroup` with `"   "` | Throw `ArgumentError` |
