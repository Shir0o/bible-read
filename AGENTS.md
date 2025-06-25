# Agent instructions

## Environment setup

To run Flutter commands in this repository, the Codex environment must set up the local Flutter SDK. The setup script should clone the Flutter repository, add the SDK to the `PATH`, and fetch dependencies.

```
# 1. Install Flutter SDK (locally in the project)
#    This clones the stable branch to a subdirectory named `flutter`.
git clone https://github.com/flutter/flutter.git -b stable flutter

# 2. Add Flutter to PATH
export PATH="$PWD/flutter/bin:$PATH"

# Run Flutter doctor to download artifacts and check the tool chain
flutter doctor

# Accept Android licenses without interactive prompts
yes | flutter doctor --android-licenses || true

# 3. Get project dependencies
flutter pub get
```

## Programmatic checks

Run `flutter test` to execute the project's automated tests before committing changes.
