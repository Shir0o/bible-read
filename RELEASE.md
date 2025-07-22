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