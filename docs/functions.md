# Cloud Functions

This document describes the Firebase Cloud Functions exported from [`functions/index.js`](../functions/index.js).

## sendLikeNotification

* **Type:** HTTPS callable.
* **Input:** `ownerUid` (UID of the log owner), `likerName` (display name of the liker).
* **Errors:**
  * `unauthenticated` if the caller is not signed in.
  * `invalid-argument` when either field is missing.
  * `internal` if Firebase Messaging fails.
* **Firestore:** Reads `users/{ownerUid}` for the `fcmToken` and checks `users/{ownerUid}/notificationPrefs/like` to respect the user's preference.
* **Returns:** Resolves with the message ID string from `admin.messaging().send()` or `undefined` when notifications are disabled or no token exists.

## sendCommentNotification

* **Type:** HTTPS callable.
* **Input:** `ownerUid` (UID of the log owner), `commenterName` (display name of the commenter).
* **Errors:**
  * `unauthenticated` if the caller is not signed in.
  * `invalid-argument` when either field is missing.
  * `internal` if Firebase Messaging fails.
* **Firestore:** Reads `users/{ownerUid}` for the `fcmToken` and checks `users/{ownerUid}/notificationPrefs/comment`.
* **Returns:** Message ID string from `admin.messaging().send()` or `undefined` if notifications are disabled or the user lacks an FCM token.

## sendSignupNotification

* **Type:** Auth trigger (`functions.auth.user().onCreate`).
* **Input:** Newly created Firebase Auth user.
* **Configuration:** Requires the `ADMIN_UID` environment variable. The function looks up `users/{ADMIN_UID}` to obtain the admin's FCM token.
* **Errors:** Logs warnings when `ADMIN_UID` or the admin token is missing and logs an error if the send operation fails.
* **Returns:** `void`.

## awardConsistencyBadges

* **Type:** Firestore trigger (`onDocumentWritten`) on `users/{uid}/summary/data`.
* **Firestore:** Reads the Showing-up summary's cumulative `totalReadDays` and awards the consistency badges (`days_7`, `days_30`, `days_50`, `days_100`, `days_365`) each new total earns, under `users/{uid}/achievements/`. Showing up counts however the day was marked — with or without a Plan. Also mirrors the biggest newly earned badge into `groups/{g}/badges/{uid}` for each of the reader's groups and writes a `badge` notification document for the reader.
* **Idempotency:** Badges are created, not set — a re-run never re-awards one or moves its `dateUnlocked`.

## awardPlanFinishedBadge

* **Type:** Firestore trigger (`onDocumentWritten`) on `users/{uid}/plan_progress/{planId}`.
* **Firestore:** When the progress document's `completedDays` covers every day of the plan's schedule (`custom_plans/{planId}`), the reader earns the `plan_finished` badge, with the mirror and notification as above. If the plan definition cannot be read, nothing is awarded rather than guessing.
* **Idempotency:** As above.

## awardReadThroughBadges

* **Type:** Firestore trigger (`onDocumentCreated`) on `users/{uid}/read_throughs/{docId}`.
* **Firestore:** Recounts the reader's read-through ledger and awards any read-through badge (`first_ot`, `first_nt`, `first_bible`, `bible_5`, `bible_10`) the new total earns, under `users/{uid}/achievements/`. Also mirrors the biggest newly earned badge into `groups/{g}/badges/{uid}` for each of the reader's groups, the path co-members can read (ADR-0004).
* **Idempotency:** Badges are created, not set — a re-run never re-awards one or moves its `dateUnlocked`.

## awardFirstBookBadge

* **Type:** Firestore trigger (`onDocumentCreated`) on `users/{uid}/bible_books/{book}`.
* **Firestore:** The collection only ever holds completed books, so when it holds exactly one document the reader earns the `first_book` badge and their groups' badge mirrors update as above.

## backfill-achievements (one-off script)

* **Type:** One-off, re-runnable script (`node functions/backfill-achievements.js`), not a deployed trigger.
* **Firestore:** For every reader holding history in `read_throughs`, `bible_books`, `plan_progress` or `summary`, re-derives each badge family from the same sources the triggers use and awards what is missing — silently: no notification documents and no FCM push, since these are milestones earned long ago. The unlock stamp is the backfill run's date; where a crossing date cannot be recovered from the ledger, no past date is invented.
* **Idempotency:** As the triggers — a second run re-derives the same earned set, finds every badge held, and writes nothing.
* **Verification:** `functions/verify-backfill-emulator.js` seeds fixtures into the Firestore emulator, runs the pass twice, and asserts derivation, stamps, mirror and no-op idempotency.


### Related Collections and Config

* `notificationPrefs` – subcollection under each user controlling notification opt‑ins.
* `ADMIN_UID` – environment variable pointing to the admin user who receives signup alerts.



## Deployment

Deploy Cloud Functions from the repository root or the `functions/` directory:

```
firebase deploy --only functions:sendLikeNotification,functions:sendCommentNotification,functions:sendSignupNotification,functions:awardReadThroughBadges,functions:awardFirstBookBadge,functions:awardConsistencyBadges,functions:awardPlanFinishedBadge
```


