#!/bin/bash
set -euxo pipefail

# ====== Config ======
FLUTTER_VERSION=3.24.3
FLUTTER_REPO=https://github.com/flutter/flutter.git

# Use a repo-local pub cache so dependencies persist across steps
export PUB_CACHE="${PUB_CACHE:-$PWD/.pub-cache}"

# ====== Install Flutter (cached per build machine, fresh per new VM) ======
if [ ! -d "$PWD/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" "$FLUTTER_REPO" flutter
fi
export PATH="$PWD/flutter/bin:$PATH"

# Disable analytics in CI and prefetch iOS artifacts up front
flutter config --no-analytics
dart --disable-analytics || true
flutter precache --ios

# Show versions for logs
flutter --version
dart --version

# ====== Flutter deps ======
flutter pub get

# ====== Generate iOS build configs (without full build) ======
flutter build ios --debug --no-codesign --simulator --config-only

# ====== iOS deps (CocoaPods) ======
pushd ios

# Avoid slow Pod repo updates unless needed; fallback if first install fails
if [ ! -f "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-input-files.xcfilelist" ]; then
  if ! pod install; then
    pod repo update
    pod install
  fi
fi

popd
