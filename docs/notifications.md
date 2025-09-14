# Notifications

This document provides an overview of how push notifications are handled in the app.

## Services and models

### NotificationPreferences and NotificationType
`NotificationType` enumerates the categories that users can enable or disable. `NotificationPreferences` stores a boolean value for each type, defaulting to `true` when data is missing so new types are automatically opted in.

### NotificationService
`NotificationService` reads and writes a user's notifications under `users/{uid}/notifications` in Firestore. It exposes a stream of notifications and helpers to mark them as read or add entries for testing.

## FCM tokens
Firebase Cloud Messaging tokens are retrieved on sign‑in and stored in the user's document under `fcmToken` so backend services can address push messages to the device.

## Cloud Functions
Cloud Functions in the `functions/` directory send push notifications. Callable functions such as `sendLikeNotification` and `sendCommentNotification` read the recipient's `fcmToken` and `notificationPrefs` to respect user settings before sending a message.

