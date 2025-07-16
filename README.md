# Bible Reading Challenge App

A Flutter application designed to help individuals and groups track their daily Bible reading, build streaks, and engage with a community.

## Features

*   **Daily Reading Tracker:** Mark each day that you read the Bible to build your streak.
*   **Weekly and Monthly Views:** See your reading progress at a glance with weekly and monthly calendar views.
*   **Leaderboard:** See how your reading streak compares to others.
*   **Reading Feed:** See who else has read the Bible today and give them a like to encourage them.
*   **User Profile:** View your profile information and sign in with your Google account.
*   **Like Notifications:** Receive a push notification when someone likes your read log.

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
