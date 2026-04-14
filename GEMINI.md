# Bible Reading Challenge App

This project is a Flutter mobile application designed to help individuals and groups track their daily Bible reading, build streaks, and engage with a community. It features daily reading tracking, a reading feed, user profiles, seasonal challenges, and Bible book progress.

The application leverages Firebase heavily for its backend services, including:
*   **Firestore:** For database operations and real-time data synchronization.
*   **Authentication:** For user sign-up and sign-in (Google Sign-In, Email/Password).
*   **Messaging (FCM):** For push notifications (e.g., likes, comments, friend requests, signup alerts).
*   **Cloud Functions:** For backend logic and event-driven tasks (Node.js).
*   **Crashlytics:** For crash reporting and error logging.
*   **App Check:** For protecting backend resources from abuse.

## Technologies Used

*   **Frontend:** Flutter (Dart SDK ^3.5.4)
*   **Backend:** Firebase (Firestore, Authentication, Messaging, Cloud Functions, Crashlytics, App Check)
*   **CI/CD:** GitHub Actions

## Building and Running

### Prerequisites

*   Flutter SDK (version 3.5.4 or higher recommended).
*   Firebase project set up with Google Sign-In enabled.
*   `google-services.json` (for Android) and `GoogleService-Info.plist` (for iOS) configured in their respective project directories.
*   Node.js 20 for Firebase Functions development.

### Installation & Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/<your-org>/bible-read.git
    cd bible-read
    ```

2.  **Install Flutter SDK (if not already installed) and dependencies:**
    ```bash
    git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
    export PUB_CACHE="$PWD/.pub-cache"
    export PATH="$PWD/flutter/bin:$PATH"
    flutter config --no-analytics
    flutter pub get
    ```

3.  **Firebase Functions Setup:**
    Navigate to the `functions` directory and install Node.js dependencies:
    ```bash
    cd functions
    npm install
    cd ..
    ```
    Set `ADMIN_UID` for signup notifications:
    ```bash
    firebase functions:config:set admin_uid="<your-admin-uid>"
    ```

### Running the Application

To run the Flutter application:
```bash
flutter run
```

To serve Firebase Functions locally:
```bash
cd functions
npm run serve
cd ..
```

### Building for Release

*   **Android:**
    ```bash
    flutter build appbundle --release --build-name=<version> --build-number=<build>
    ```
*   **iOS:**
    ```bash
    flutter build ipa --release --build-name=<version> --build-number=<build>
    ```

## Testing

### Flutter Tests

To run Flutter unit and widget tests:
```bash
flutter test --no-pub
```

To run integration tests:
```bash
flutter test integration_test/
```
(Specific integration test files: `integration_test/first_reader_test.dart`, `integration_test/main_flow_test.dart`)

### Firebase Functions Tests

To run tests for Firebase Cloud Functions:
```bash
cd functions
npm test
cd ..
```

### CI/CD

The project uses GitHub Actions for continuous integration.
*   **Flutter tests** are run on `ubuntu-latest` using `flutter test --no-pub --fail-fast`.
*   **Firebase Functions tests** are run on `ubuntu-latest` using `npm test` in the `functions/` directory.

## Development Conventions

### Code Formatting and Analysis

The project adheres to Flutter's recommended linting rules, specified in `analysis_options.yaml`, which includes `package:flutter_lints/flutter.yaml`. Additionally, `prefer_single_quotes: true` is enforced.

To format and analyze Dart code:
```bash
dart format lib test
flutter analyze
```

Firebase Cloud Functions follow ESLint rules defined in `eslint.config.cjs`. To lint functions code:
```bash
cd functions
npm run lint
cd ..
```

### Optimistic UI Updates

The application prioritizes a zero-latency user experience by employing Optimistic UI updates for high-frequency interactions (e.g., marking readings as complete, toggling likes, manual Bible book tracking). 

**Key Requirements:**
*   **Immediate Feedback:** UI state must update immediately upon user interaction using local state overrides, **without waiting for API/backend success**.
*   **Background Sync:** Backend requests (Firestore, Cloud Functions) should be initiated in the background without blocking the UI.
*   **Conflict Resolution:** Local overrides must be cleared or synchronized once the backend "source of truth" (typically a Stream) reflects the change.
*   **Rollback Mechanism:** In the event of a backend failure, the UI must gracefully revert to its previous state and notify the user (e.g., via a SnackBar).

### Skeleton Loaders

The application uses skeleton loaders to provide a smooth transition while content is loading.

**Key Requirements:**
*   **Minimum Duration:** Skeleton loaders must be visible for a minimum of **1000ms** to prevent UI flashing during fast network responses. This is typically achieved using `SkeletonLoader.minTime` or an artificial `Future.delayed` in data fetching methods.
*   **Persistent Titles:** Page and section titles should remain visible while their content is loading. Skeleton loaders should only replace the data-dependent components (e.g., cards, lists), not the headers themselves. This maintains layout stability and provides context to the user while they wait.

### Error Logging and Crash Reporting

Firebase Crashlytics is integrated for crash reporting. Crashlytics collection is enabled only in non-debug builds. Global error handlers are registered in `lib/main.dart` to log errors via the `ErrorLogger` service.

### Notifications

Firebase Messaging is used for push notifications. The `lib/main.dart` handles incoming messages and navigation based on notification data. Local notifications are managed by `flutter_local_notifications`. New notification types can be added by defining them in `NotificationType` and managing user preferences in `notificationPrefs`.

### Customizing Colors

The app's color scheme is defined in `lib/theme/app_theme.dart`. `AppTheme.backgroundColor` and `AppTheme.appTheme` control the main background and scaffold colors.

### Vibration

Haptic feedback is provided using the `vibration` package and `VibrationService` (in `lib/services/vibration_service.dart`). Vibration can be toggled in settings.

## Documentation

Additional documentation is available in the `docs/` directory, covering topics such as:
*   `docs/cache.md`: Badge image caching.
*   `docs/coverage.md`: Test coverage reports.
*   `docs/functions.md`: Cloud Function details.
*   `docs/groups.md`: Details on group reading.
*   `docs/notifications.md`: Notification services and preferences.