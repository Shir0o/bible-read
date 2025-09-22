# Notifications

This document provides an overview of how push notifications are handled in the app.

## Services and models

### NotificationPreferences and NotificationType
`NotificationType` enumerates the categories that users can enable or disable. `NotificationPreferences` stores a boolean value for each type, defaulting to `true` when data is missing so new types are automatically opted in.

The current notification types map to icons, copy, and navigation targets as follows:

| Type | Icon | Message | Destination |
| ---- | ---- | ------- | ----------- |
| `like` | `Icons.thumb_up` | "Someone liked your reading" | None |
| `nudge` | `Icons.notifications_active` | "You were nudged to read" | None |
| `signup` | `Icons.person_add` | "New signup" | None |
| `achievement` | `Icons.emoji_events` | "Achievement unlocked" | Achievements page |
| `friendRequest` | `Icons.person_add_alt` | "You received a friend request" | Friend Requests page |
| `comment` | `Icons.comment` | "New comment on your reading" | None |
| `groupJoinRequest` | `Icons.group_add` | "You received a group join request" | None |
| `groupScheduleUpdate` | `Icons.schedule` | "Group schedule updated" | None |
| `seasonalChallenge` | `Icons.eco` | "Seasonal challenge reward ready" | Seasonal Challenges page |

### NotificationService
`NotificationService` reads and writes a user's notifications under `users/{uid}/notifications` in Firestore. It exposes a stream of notifications and helpers to mark them as read or add entries for testing.

## FCM tokens
Firebase Cloud Messaging tokens are retrieved on sign‑in and stored in the user's document under `fcmToken` so backend services can address push messages to the device.

## Cloud Functions
Cloud Functions in the `functions/` directory send push notifications. Callable functions such as `sendLikeNotification` and `sendCommentNotification` read the recipient's `fcmToken` and `notificationPrefs` to respect user settings before sending a message.

