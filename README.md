# Bible Reading Challenge App

A Flutter application designed to help individuals and groups track their daily Bible reading, build streaks, and engage with a community.

## Features

*   **Daily Reading Tracker:** Mark each day that you read the Bible to build your streak.
*   **Weekly and Monthly Views:** See your reading progress at a glance with weekly and monthly calendar views.
*   **Leaderboard:** Compare streaks with the public and with your friends on a new tabbed leaderboard, which now shows your own ranking.
*   **Reading Feed:** See who else has read the Bible today and give them a like to encourage them.
*   **User Profile:** View your profile information and sign in with your Google account or with an email and password.
*   **Like Notifications:** Receive a push notification when someone likes your read log.
*   **Nudge Friends:** Remind friends to read by sending a nudge notification.
*   **Signup Notification:** The admin user receives a push notification whenever someone creates an account.
*   **Customizable Notifications:** Choose which notifications you receive from the settings page.
*   **Permanent Likes:** Likes cannot be removed once given.
*   **Friends Page:** Manage friends on a dedicated page and send new requests using the **+** button.
*   **Add Friend Page:** The **+** button opens a separate page for sending friend requests.
*   **Achievements:** Unlock achievements like being the first reader of the day and view them from the Achievements page.

### Signup Notification Setup

The Cloud Function `sendSignupNotification` sends a push notification to the user specified by `ADMIN_UID` whenever a new account is created. Set `ADMIN_UID` using Firebase Functions config before deploying:

```bash
firebase functions:config:set admin_uid="<your-admin-uid>"
```

Deploy the functions after setting the value so the admin receives signup alerts.

## Customizing Colors

The scaffold and app bar backgrounds are defined in
`lib/theme/app_theme.dart`. Update `AppTheme.backgroundColor` or the
`scaffoldBackgroundColor` value in `AppTheme.appTheme` to change the colors
across the app.

## Adding Notification Types

Define a new value in `NotificationType` and store a boolean under the
`notificationPrefs` subcollection for each user. Missing entries default to
`true`, so existing users automatically opt into new notifications. When you
send a push message you can also save it in a `notifications` subcollection
using the `AppNotification` model so the app can display a history of alerts.

## Getting Started

This project is a starting point for a Flutter application.

### Prerequisites

*   Flutter SDK installed (version 3.5.4 or higher recommended).
*   Firebase project set up with Google Sign-In enabled.
*   `google-services.json` (for Android) and `GoogleService-Info.plist` (for iOS) configured in their respective project directories.

### Installation

1.  Clone the repository:

    ```bash
    git clone https://github.com/your-repo/bible_read.git
    cd bible_read
    ```

2.  Fetch dependencies:

    ```bash
    flutter pub get
    ```

3.  Run the app:

    ```bash
    flutter run
    ```

### Creating an Account Without Google

After launching the app open the profile tab and choose **Email Sign Up** to
create a new account using your email address. Use **Email Sign In** on later
launches to log in with those credentials.

## Installing Flutter

The integration tests bundled with this project require a local Flutter SDK.
If the SDK is missing they will be skipped.

The simplest way to install Flutter for local development is to clone the
official repository and run its setup scripts. The installation downloads
artifacts from `storage.googleapis.com` so make sure your network allows access
to that domain.

```bash
# Clone the stable channel of the Flutter SDK into a directory named `flutter`
git clone https://github.com/flutter/flutter.git -b stable flutter

# Add Flutter to your PATH
export PATH="$PWD/flutter/bin:$PATH"

# Run Flutter doctor to download dependencies
flutter doctor
```

Once the SDK is installed you can fetch project dependencies with:

```bash
flutter pub get
```

After installation the Flutter commands such as `flutter test` will be available.

## Development

Run the formatter, analyzer, and tests after making changes:

```bash
flutter format .
flutter analyze
flutter test
```

## Releasing on iOS

1.  Build the release IPA with your desired version and build number:

    ```bash
    flutter build ipa --release --build-name=<version> --build-number=<build>
    ```

2.  Open the iOS project in Xcode to verify the version and build number on the
    **General** tab.
3.  Enable automatic signing in Xcode and update any provisioning profiles if
    needed.
