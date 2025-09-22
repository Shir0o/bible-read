# Bible Reading Challenge App

A Flutter application designed to help individuals and groups track their daily Bible reading, build streaks, and engage with a community.

## Features

*   **Daily Reading Tracker:** Mark each day that you read the Bible to build your streak.
*   **Weekly and Monthly Views:** See your reading progress at a glance with weekly and monthly calendar views.
*   **Leaderboard:** Compare streaks with the public and with your friends on a new tabbed leaderboard, which now shows your own ranking.
*   **Reading Feed:** See who else has read the Bible today and give them a like to encourage them.
*   **User Profile:** View your profile information and sign in with your Google account or with an email and password.
*   **Like Notifications:** Receive a push notification when someone likes your read log.
*   **Comments:** Reply to others in the feed by leaving comments on their logs. Tap the comment icon to open a drawer showing all replies and a field to add your own.
*   **Comment Notifications:** Get notified when someone comments on your reading.
*   **Nudge Friends:** Remind friends to read by sending a nudge notification.
*   **Signup Notification:** The admin user receives a push notification whenever someone creates an account.
*   **Customizable Notifications:** Choose which notifications you receive from the settings page.
*   **Permanent Likes:** Likes cannot be removed once given.
*   **Friends Page:** Manage friends on a dedicated page and send new requests using the **+** button.
*   **Groups Page:** Browse all reading groups, create or join them, and open any group to view its members and daily chapter assignments. See [docs/groups.md](docs/groups.md) for details on group reading.
*   **Add Friend Page:** The **+** button opens a separate page for sending friend requests.
*   **Notification Center:** Recent alerts are stored in-app and can be viewed from the bell icon while your notification preferences still control which ones trigger push messages.
*   **Seasonal Challenges:** Join limited-time challenges, track progress from the
    home dashboard, and visit the Seasonal tab to claim exclusive rewards before the
    season ends.
*   **Achievements:** Unlock evergreen badges such as being the first reader of the day and view them from the Achievements page.
### Posting Comments

Each entry in the reading feed includes a comment field labeled "Add a comment..." with a **Post** button so you can reply to others. Comments appear above the field after posting.
Commenting was introduced in version 1.9.0.

When someone comments on your reading, the `sendCommentNotification` function sends a push notification using the new `NotificationType.comment` setting.

Firestore permissions allow any signed-in user to read comments, authors to create them with their UID, and either the author or entry owner to delete them.


## Achievements

The app currently offers the following achievements. Badge icons are provided by the [Font Awesome](https://fontawesome.com) library via [`font_awesome_flutter`](https://pub.dev/packages/font_awesome_flutter).

| Icon | ID | Description |
| ---- | -- | ----------- |
| ![book-open-reader](https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.5.1/svgs/solid/book-open-reader.svg) | `firstReader` | Be the first person to log reading for the day. |
| ![fire](https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.5.1/svgs/solid/fire.svg) | `streak7` | Read the Bible seven days in a row. |
| ![calendar-check](https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.5.1/svgs/solid/calendar-check.svg) | `days30` | Log 30 days of reading. |
| ![fire-flame-curved](https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.5.1/svgs/solid/fire-flame-curved.svg) | `streak30` | Read every day for a full month. |

In addition to these evergreen achievements, rotating seasonal challenges provide
time-boxed goals with bespoke rewards. Each season defines its own set of
challenges and prizes—such as bonus points, exclusive badges, or limited
artwork—that appear on the **Seasonal** tab and in the seasonal summary on the home
page. Progress updates whenever you read, and once a goal is completed you can
claim the reward directly from the Seasonal Challenges page; a notification is also
saved in the Notification Center so the reward is easy to find later.

Achievements are displayed in a scrollable list where each row shows the badge,
title and description. Locked items are overlaid with a lock icon until they are
earned.

### Remote icons and badges

Achievement icons above are loaded from Font Awesome over the network. This keeps
the repository light, but the images will not appear when the README is viewed
offline. To host or update badges:

1. Upload the image to a publicly accessible location such as a CDN or another
   GitHub repository.
2. Replace the image URL in this document with the new hosted link.
3. Ensure the host allows hotlinking so the badge renders correctly.

### Badge image caching

Badge images downloaded in the app are cached locally to minimize
bandwidth. See [docs/cache.md](docs/cache.md) for details on how caching
works and how to clear stored images.

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

## Vibration

The app can vibrate the device to provide haptic feedback for certain actions.
Vibration is enabled by default and may be toggled from the Settings page under
**Vibration**.

The [VibrationService](lib/services/vibration_service.dart) exposes a
`tap()` helper for a light impact. Widgets can obtain the service by reading a
global instance from a `Provider` or by accepting a [VibrationService]
through their constructors. For example, `AnimatedActionButton` accepts a
`vibrationService` parameter that defaults to `const VibrationService()`.

Vibration requires hardware support and is not available on all platforms.
Devices without a vibration motor—including many tablets, web browsers, and
desktop environments—will ignore the setting. Simulators and emulators may also
skip vibration even when a physical device supports it.

## Getting Started

This project is a starting point for a Flutter application.

### Prerequisites

*   Flutter SDK installed (version 3.5.4 or higher recommended).
*   Firebase project set up with Google Sign-In enabled.
*   `google-services.json` (for Android) and `GoogleService-Info.plist` (for iOS) configured in their respective project directories.

### Installation

1.  Clone the repository:

    ```bash
    git clone https://github.com/<your-org>/bible-read.git
    cd bible-read
    ```

2.  Install the Flutter SDK and fetch dependencies:

    ```bash
    git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
    export PUB_CACHE="$PWD/.pub-cache"
    export PATH="$PWD/flutter/bin:$PATH"
    flutter config --no-analytics
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
Clone the SDK into the repository and add it to your path:

```bash
git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
export PUB_CACHE="$PWD/.pub-cache"
export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter pub get
```

## Development

Install Flutter as shown above. After making changes, run the
following programmatic checks to format, analyze, and test your code:

```bash
dart format lib test
flutter analyze
flutter test --no-pub
```

Developers working on backend features can find Cloud Function details in
[docs/functions.md](docs/functions.md). Notification services and preferences
are outlined in [docs/notifications.md](docs/notifications.md).

### Coverage

Instructions for generating test coverage reports are available in
[docs/coverage.md](docs/coverage.md).

## Crashlytics

The app integrates Firebase Crashlytics through the
`firebase_crashlytics` dependency listed in `pubspec.yaml`. Crashlytics is
initialized in [`main.dart`](lib/main.dart) where lines 20–37 enable collection
only when `kDebugMode` is `false` and register global error handlers that call
the [`ErrorLogger` service](lib/services/error_logger.dart).

To start receiving crash reports:

1.  Open your project in the Firebase console.
2.  Navigate to **Build** → **Crashlytics** and click **Enable**.
3.  Run the app in release mode to send the first crash.

Crash reports and logs are viewable on the Crashlytics dashboard under
**Build** → **Crashlytics**. Because `setCrashlyticsCollectionEnabled` is passed
`!kDebugMode`, logs are collected only from non-debug builds.

## Releasing on iOS

1.  Build the release IPA with your desired version and build number:

    ```bash
    flutter build ipa --release --build-name=<version> --build-number=<build>
    ```

2.  Open the iOS project in Xcode to verify the version and build number on the
    **General** tab.
3.  Enable automatic signing in Xcode and update any provisioning profiles if
    needed.

## Releasing on Android

1.  Build the release app bundle with your desired version and build number:

    ```bash
    flutter build appbundle --release --build-name=<version> --build-number=<build>
    ```

2.  Upload the generated `.aab` file to the Google Play Console for distribution.

## Licenses and Attributions

- Achievement badges in this README use icons from the [Font Awesome Free](https://fontawesome.com) set, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- The success animation uses [`scan_qr_code_success.json`](https://raw.githubusercontent.com/xvrh/lottie-flutter/master/example/assets/lottiefiles/scan_qr_code_success.json) from the [xvrh/lottie-flutter](https://github.com/xvrh/lottie-flutter) project, licensed under [MIT](https://raw.githubusercontent.com/xvrh/lottie-flutter/master/LICENSE).

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for full details.
