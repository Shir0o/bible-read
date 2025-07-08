# bible_read

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Installing Flutter

The integration tests bundled with this project require a local Flutter SDK. If the SDK is missing they will be skipped.

The simplest way to install Flutter for local development is to clone the official repository and run its setup scripts. The installation downloads artifacts from `storage.googleapis.com` so make sure your network allows access to that domain.

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
