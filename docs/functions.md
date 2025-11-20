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
* **Schedule:** Runs at 09:00 UTC on the first day of each month (`0 9 1 * *`) with the scheduler timezone pinned to `Etc/UTC` to avoid daylight-saving drift.
* **Configuration:** Uses SendGrid and requires the following config keys or environment variables:
  * `functions.config().sendgrid.apikey` or `SENDGRID_API_KEY` – SendGrid API key.
  * `functions.config().sendgrid.from` or `SENDGRID_FROM` – Verified sender address.
  * `functions.config().sendgrid.to` or `SENDGRID_TO` – Optional default recipient list for ad‑hoc tests.
* **Opt-in behavior:** Each user can toggle `emailPrefs.monthlySummary` in their profile document. The job sends to verified Auth emails only and defaults to **on** when the flag is absent.
* **Firestore:** Reads the `users` collection for recipient metadata and uses `monthly-stats.js` to gather the previous month's reading coverage from summary/reading/read_logs data.
* **Email content:** Subject `Your <Month Year> reading summary` with both text and HTML bodies:
  * Greeting with the user's display name (e.g., `Hi Jane,`).
  * Bulleted stats for days read, the longest streak and count of streak segments, and grace days used.
  * Closing encouragement (“Keep up the great work! 🕊️”).
* **Resource limits:** Capped at `maxInstances: 1` to control costs.

### Local testing

1. Install and build functions: `cd functions && npm ci`.
2. Provide SendGrid config locally via `firebase functions:config:set sendgrid.apikey="<key>" sendgrid.from="you@example.com"` (and optionally `sendgrid.to`) or export the equivalent environment variables before running the emulator.
3. Start the Functions emulator: `firebase emulators:start --only functions`.
4. In another terminal, invoke the scheduled function manually with the shell to simulate the cron trigger: `firebase functions:shell --only sendMonthlyStatsEmail` then run `sendMonthlyStatsEmail()`.
5. Check emulator logs (and the configured inbox if using a real SendGrid key) for the rendered email that matches the bullet points above.

## Deployment

Deploy Cloud Functions from the repository root or the `functions/` directory:

```
firebase deploy --only functions:sendLikeNotification,functions:sendCommentNotification,functions:sendSignupNotification,functions:markFirstReader,functions:sendMonthlyStatsEmail
```

The deployment command also provisions the Cloud Scheduler job that triggers `sendMonthlyStatsEmail`.
