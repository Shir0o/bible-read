#!/bin/bash
set -euxo pipefail

echo "=== ci_post_clone: starting bootstrap ==="

# ====== Config ======
FLUTTER_VERSION=3.35.6
FLUTTER_REPO=https://github.com/flutter/flutter.git

# Use a repo-local pub cache so dependencies persist across steps
export PUB_CACHE="${PUB_CACHE:-$PWD/.pub-cache}"

# ====== Install Flutter (cached per build machine, fresh per new VM) ======
if [ ! -d "$PWD/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" "$FLUTTER_REPO" flutter
else
  echo "=== ci_post_clone: Flutter cache detected, ensuring tag $FLUTTER_VERSION is checked out ==="
  pushd flutter
  CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || true)
  if [ "$CURRENT_TAG" != "$FLUTTER_VERSION" ]; then
    echo "=== ci_post_clone: updating cached Flutter checkout to $FLUTTER_VERSION ==="
    git fetch --depth 1 origin "refs/tags/$FLUTTER_VERSION"
    git checkout --force "$FLUTTER_VERSION"
    git reset --hard
    git clean -fdx
  fi
  popd
fi
echo "=== ci_post_clone: ensuring Flutter SDK ($FLUTTER_VERSION) is available ==="
export PATH="$PWD/flutter/bin:$PATH"

# Disable analytics in CI and prefetch iOS artifacts up front
echo "=== ci_post_clone: disabling analytics and precaching iOS artifacts ==="
flutter config --no-analytics
dart --disable-analytics || true
flutter precache --ios

# Show versions for logs
echo "=== ci_post_clone: Flutter & Dart versions ==="
flutter --version
dart --version

# ====== Flutter deps ======
echo "=== ci_post_clone: fetching Flutter package dependencies ==="
flutter pub get

# ====== Generate iOS build configs (without full build) ======
echo "=== ci_post_clone: generating iOS build configs (debug, simulator) ==="
flutter build ios --debug --no-codesign --simulator --config-only

# ====== iOS deps (CocoaPods) ======
echo "=== ci_post_clone: resolving CocoaPods dependencies ==="
pushd ios

# Avoid slow Pod repo updates unless needed; fallback if first install fails
if [ ! -f "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-input-files.xcfilelist" ]; then
  echo "=== ci_post_clone: Pods cache missing, running pod install ==="
  if ! pod install; then
    echo "=== ci_post_clone: pod install failed, updating repo and retrying ==="
    pod repo update
    pod install
  fi
else
  echo "=== ci_post_clone: existing Pods artifacts detected, skipping pod install ==="
fi

popd

echo "=== ci_post_clone: bootstrap complete ==="
