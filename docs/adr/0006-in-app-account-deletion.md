# ADR 0006: In-app account deletion

- Status: Accepted
- Date: 2026-09-10

## Context

Both Apple App Store Review Guideline 5.1.1(v) and Google Play Data Safety policies strictly require that any mobile application allowing account creation must provide an explicit in-app mechanism for users to initiate permanent account and data deletion.

While a web-based account deletion notice was published (`docs/delete-account/index.html`), `SettingsPage` previously lacked an in-app button, creating an immediate blocker for production store reviews.

Vocabulary in this record adheres to [CONTEXT.md](../../CONTEXT.md) (Account deletion, Shown up, Circle).

## Decision

1. **In-App Entry Point in Settings**:
   Add a clear "Delete Account" action tile under an "Account" section on `SettingsPage`. The tile uses destructive styling (theme error color) to communicate risk clearly.

2. **Irreversible Confirmation Dialog**:
   Tapping "Delete Account" prompts an `AlertDialog` warning the reader that all reading history, streaks, reflections, plan progress, and group memberships will be permanently deleted and cannot be undone.

3. **Cascading Personal Data Cleanup**:
   When confirmed, the client orchestrates:
   - Deleting the user's personal Firestore document tree: `users/{uid}` and subcollections (`summary`, `settings`, `plan_progress`, `reflections`).
   - Removing the user's member document from all joined groups (`groups/{groupId}/members/{uid}`).
   - Deleting the Firebase Authentication user record (`currentUser.delete()`).

4. **Re-Authentication Handling**:
   Firebase Authentication requires a recent sign-in before account deletion. If `currentUser.delete()` throws `FirebaseAuthException` with code `requires-recent-login`, the app catches the error, displays an informative SnackBar ("Please sign in again before deleting your account for security"), signs out, and routes the user back to the sign-in screen rather than failing silently or crashing.

5. **Navigation & Session Teardown**:
   Following successful deletion, the user session is closed, local caches cleared, and the navigator redirects to the Welcome / Auth selection screen.

## Considered Options

- **Redirect to external web deletion page**: Rejected because Apple App Store Guideline 5.1.1(v) explicitly forbids requiring users to browse to a website if account creation happened in-app.
- **Server-only Cloud Function trigger (`onUserDeleted`)**: While clean, client-side immediate cleanup ensures responsive UI feedback and guarantees Firestore documents are wiped before or alongside auth deletion without relying on eventual Cloud Function execution under rate limits.
