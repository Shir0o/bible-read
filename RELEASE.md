# Release 1.9.0

This release adds commenting to the reading feed and notifications for new comments.

## Features

*   **Comments:** Users can now leave comments on reading log entries.
*   **Comment Notifications:** The new `sendCommentNotification` Cloud Function notifies you when someone comments on your reading.

# Release 1.8.0

This release introduces daily reminder notifications to help you stay consistent with your reading.

## Features

*   **Daily Reading Reminder:** Enable a daily notification from the Settings page to be reminded when you haven't logged a reading.
*   Users can now customize their notification preferences to enable or disable the daily reminder.

## Fixes
* Added tests to verify that the daily reminder is scheduled correctly.
* Updated dependencies and fixed issues with the daily reminder tests.

# Release 1.7.0

This release introduces a Notification Center, enhances the user experience with visual cues for first readers, and includes several under-the-hood improvements.

## Features

*   **Notification Center:** A new page to view and manage notifications.
*   **First Reader Recognition:** A trophy icon is now displayed for the first reader of the day.

## Enhancements

*   The friend requests button has been updated to a more general notification button.
*   Improved data handling with a new `AppNotification` model and `NotificationService`.

## Fixes

*   Resolved an issue with tests by properly injecting the `NotificationService`.
*   Removed unused code related to achievements.

## Security

*   Updated Firestore rules to support the new notification system.

# Release 1.6.0

This release introduces achievements and notification preferences.

## Features

*   **Achievements:** Users can now earn achievements for reading streaks and being the first to read for the day.
*   **Notification Preferences:** Users can now customize which notifications they receive.

# Release 1.5.3

This release introduces several new features, enhancements, and bug fixes to improve the user experience.

## Features

*   **First Reader of the Day:** The first person to read each day will now be specially marked.
*   **Signup Notifications:** New users will receive a notification upon signing up.
*   **Nudge Tracking:** The app now tracks sent nudges, disabling the button for the rest of the day to avoid spamming.
*   **Customizable Notifications:** Users can toggle which notifications they receive.

## Enhancements

*   **UI Animations:**
    *   Page transitions are now animated for a smoother experience.
    *   Navigation icons, the like icon, and the friend request badge are now animated.
    *   A new animated switch tile has been added.
*   **Friend Requests Button:** The friend requests button icon has been updated.
*   **Nudge Notification Status:** The app now returns a status from nudge notifications.
*   **Race Condition Prevention:** A transaction is now used when writing a read log to prevent race conditions.
*   **Leaderboard:** The signed-in user is now included in the friends leaderboard.

## Fixes

*   **Like Removal:** Users can no longer remove a like.
*   **Leaderboard Test:** The leaderboard friends tab test has been fixed.
*   **App Check:** The app now uses `appAttest` for the Apple provider in App Check.

# Release 1.5.2

This release includes minor updates and fixes.

## Updates

*   Updated `google-services.json` file.

# Release 1.5.1

This release includes bug fixes and improvements.

# Release 1.5.0

This release introduces a nudge feature and includes several important security and stability improvements.

## Features

*   **Nudge Notifications:** You can now send a "nudge" notification to a friend to remind them to read.

## Enhancements

*   **Improved Error Handling:** Added more robust error handling for various features, including Firestore writes, FCM messaging, and sign-out.
*   **Security Rules:** Updated and improved Firestore security rules for better data protection.

# Release 1.4.0

This release focuses on improving the user experience with a new friends leaderboard and optimistic UI updates for key interactions.

## Features

*   **Friends Leaderboard:** A new "Friends" tab has been added to the leaderboard, allowing you to see how you rank among your friends.

## Enhancements

*   **Optimistic UI Updates:**
    *   Liking a read log now provides immediate visual feedback, updating the UI before the network request completes.
    *   Toggling the "read" status is now instantaneous, making the interface feel more responsive.

# Release 1.3.0

This release introduces email and password authentication, allowing users to sign up and log in without a Google account. It also includes other enhancements and bug fixes.

## Features

*   **Email and Password Authentication:** Users can now create an account and log in using their email and password.
*   **Permanent Likes:** Likes on the reading feed are now persistent.

## Enhancements

*   **Home Page Optimization:** Improved the performance of the home page by avoiding unnecessary loading indicators when toggling the reading status.
*   **Refactored App Bar:** The app bar style has been updated to use theme colors for better consistency.

## Bug Fixes

*   **Sign-out:** Improved sign-out functionality and error logging.

# Release 1.2.3

This update introduces a complete friends system.

## Features

* Dedicated **Friends** page accessible from the bottom navigation bar.
* Floating **+** button to send friend requests by email.
* Notification icon shows the number of pending requests and opens the request list.
* Accept or decline requests directly from the new Friend Requests page.

# Release 1.2.2

This release introduces push notifications when your read log receives a like.

## Enhancements

* Stores the user's FCM token in Firestore after sign‑in.
* Cloud Function `sendLikeNotification` sends a push when another user likes your log.
* Incoming messages are shown using local notifications while the app is running.

# Release 1.2.1

This release includes minor updates and fixes.

## Updates

*   Updated `google-services.json` file.

# Release 1.2.0

This release focuses on improving the user experience by addressing loading states and ensuring consistent messaging across different sections of the app.

## Enhancements

*   **Improved Loading States:** Removed infinite loading indicators on the Feed, Leaderboard, and Home pages when the user is not signed in.
*   **Clear User Authentication Messaging:** Implemented a clear "User not signed in" message on the Feed, Leaderboard, and Home pages when the user is not authenticated, replacing previous loading states.
*   **Font Consistency:** Ensured the "User not signed in" message across all relevant pages uses the consistent `IBMPlexMono` font family.

# Release 1.1.0

This is the initial release of the Bible Reading Challenge app. This app is designed to help you stay motivated and consistent with your Bible reading. You can track your daily reading, build a streak, and see how you rank on the leaderboard.

## Features

*   **Daily Reading Tracker:** Mark each day that you read the Bible to build your streak.
*   **Weekly and Monthly Views:** See your reading progress at a glance with weekly and monthly calendar views.
*   **Leaderboard:** See how your reading streak compares to others.
*   **Reading Feed:** See who else has read the Bible today and give them a like to encourage them.
*   **User Profile:** View your profile information and sign in with your Google account.