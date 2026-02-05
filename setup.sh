#!/bin/bash
# This script sets up the development environment for the bible-read project.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Flutter Setup ---
echo "INFO: Checking Flutter installation..."
if ! command -v flutter &> /dev/null
then
    echo "ERROR: Flutter SDK not found. Please install Flutter and add it to your PATH."
    echo "Installation guide: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "INFO: Getting Flutter dependencies..."
flutter pub get

# --- Firebase Functions Setup ---
echo "INFO: Setting up Firebase Functions..."
if [ -d "functions" ]; then
  cd functions
  if [ -f "package.json" ]; then
    echo "INFO: Installing npm dependencies for Firebase Functions..."
    npm install
  else
    echo "WARNING: 'functions/package.json' not found. Skipping npm install."
  fi
  cd ..
else
  echo "WARNING: 'functions' directory not found. Skipping Firebase Functions setup."
fi

# --- OS-specific Setup ---
if [[ "$(uname)" == "Darwin" ]]; then
  echo "INFO: Running macOS-specific setup..."

  # --- iOS Setup ---
  if [ -d "ios" ]; then
    cd ios
    echo "INFO: Installing CocoaPods dependencies for iOS..."
    pod install
    cd ..
  else
    echo "WARNING: 'ios' directory not found. Skipping iOS setup."
  fi

  # --- macOS Setup ---
  if [ -d "macos" ]; then
    cd macos
    echo "INFO: Installing CocoaPods dependencies for macOS..."
    pod install
    cd ..
  else
    echo "WARNING: 'macos' directory not found. Skipping macOS setup."
  fi
else
  echo "INFO: Skipping macOS-specific setup on non-macOS system."
fi

echo "✅ Setup complete! You are ready to develop."
