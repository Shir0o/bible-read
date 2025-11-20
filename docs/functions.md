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

## markFirstReader

* **Type:** HTTPS callable.
* **Input:** `dateKey` (YYYY-MM-DD string identifying the day).
* **Firestore:**
  * Checks and writes to `daily_rewards/{dateKey}` to record the first reader.
  * Reads and updates entries under `read_logs/{dateKey}/entries`.
* **Errors:**
  * `unauthenticated` if the caller is not signed in.
  * `invalid-argument` when `dateKey` is missing.
  * `failed-precondition` if no log entries exist for the specified day.
  * `internal` for unexpected transaction failures.
* **Returns:** `{ first: boolean }` indicating whether the caller was the first reader.

### Related Collections and Config

* `notificationPrefs` – subcollection under each user controlling notification opt‑ins.
* `ADMIN_UID` – environment variable pointing to the admin user who receives signup alerts.

## sendMonthlyStatsEmail

* **Type:** Scheduled Pub/Sub (Functions v2).
* **Schedule:** Runs at 09:00 UTC on the first day of each month (`0 9 1 * *`).
* **Configuration:** Uses the shared SendGrid settings (`sendgrid.apikey`, `sendgrid.from`) to deliver messages.
* **Firestore:** Reads the `users` collection for recipients and the `entries` collection group for the previous month's reading activity.
* **Resource limits:** Capped at `maxInstances: 1` to control costs.
* **Behavior:** Generates a monthly summary per user (days read, entries logged, and chapters tracked) and emails the results.

## Deployment

Deploy Cloud Functions from the repository root or the `functions/` directory:

```
firebase deploy --only functions:sendLikeNotification,functions:sendCommentNotification,functions:sendSignupNotification,functions:markFirstReader,functions:sendMonthlyStatsEmail
```

The deployment command also provisions the Cloud Scheduler job that triggers `sendMonthlyStatsEmail`.
