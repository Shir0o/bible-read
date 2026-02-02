# Stress Audit Report

**Date:** October 26, 2023
**Auditor:** Jules (Senior Test Architect)

## Objective 1: Test Integrity Audit

### Shallow Assertions
*   **Location:** `GroupService` tests (e.g., `recalcProgressForUserInGroup`).
*   **Issue:** Some tests verify that a value was written (e.g., `count: 2`) but do not fully verify the surrounding state or side effects on the `progressSummary` in all edge cases.
*   **Risk:** Low. The critical path seems covered, but subtle state corruptions might be missed.

### Mocks & Isolation
*   **Location:** `test/services/group_service_test.dart` (Error Handling group).
*   **Issue:** Tests heavily mock the `FirebaseFirestore` call chain (collection -> doc -> collection -> ...). This matches the implementation exactly ("tautological testing").
*   **Risk:** Medium. Refactoring the service implementation (e.g., changing how references are built) will break these tests even if logic remains correct.

### Brittleness
*   **Location:** `ReferenceParser` (`normalizeOne` vs `_parseEndpoint`).
*   **Issue:** Logic for parsing "Book Chapter" strings is duplicated between `normalizeOne` and `_parseEndpoint`.
*   **Risk:** High. Inconsistencies have been found (see Gap Analysis) where one method rejects input that the other coerces.

### Flakiness Risk
*   **Location:** `GroupService` (streams).
*   **Issue:** Some tests rely on `emitsThrough` or `firstWhere`, which can be flaky if the stream emits unexpected intermediate values.
*   **Risk:** Low. `fake_cloud_firestore` is generally deterministic.

## Objective 2: Gap Analysis

### Data Integrity (Critical)
*   **Scenario:** Inputting "Gen 0".
*   **Current Behavior:** `ReferenceParser.parseChaptersList('Gen 0')` silently coerces this to "Genesis 1". `ReferenceParser.normalizeOne('Gen 0')` correctly identifies it as invalid ("Gen 0").
*   **Impact:** Users typing typos might get valid but incorrect data saved to their schedule without warning.

### Missing Scenarios
*   **Reversed Ranges:** "John 5-3". The code supports this (swaps to 3-5), but no test explicitly verifies it. This is a "hidden feature" that could regress.
*   **Partial Failures:** `GroupService.deleteGroup` performs best-effort cleanup. No tests verify that the main group document is still deleted even if a subcollection delete fails.

## Test Debt Summary

| Priority | Component | Issue | Remediation |
| :--- | :--- | :--- | :--- |
| **High** | `ReferenceParser` | Silent coercion of "Chapter 0" to "Chapter 1". | Refactor `_parseEndpoint` to reject invalid chapters strictuly. |
| **Medium** | `ReferenceParser` | Logic duplication between `normalizeOne` and `_parseEndpoint`. | Refactor to share parsing logic (out of scope for immediate fix but noted). |
| **Low** | `GroupService` | Brittle mock-heavy error tests. | Use a wrapper or facade for Firestore if refactoring later. |

## Proposed New Tests

| Scenario | Input | Expected Outcome | Rationale |
| :--- | :--- | :--- | :--- |
| **Zero Chapter** | `ReferenceParser.parseChaptersList('Gen 0')` | `['Gen 0']` (Invalid/Raw) | Prevent silent data corruption where 0 becomes 1. |
| **Reversed Range** | `ReferenceParser.parseChaptersList('John 5-3')` | `['John 3', 'John 4', 'John 5']` | Ensure robust handling of user typos/ranges. |
| **Mixed Invalid** | `ReferenceParser.parseChaptersList('Gen 0; Ex 1')` | `['Gen 0', 'Exodus 1']` | Verify mixed valid/invalid inputs are handled safely. |
