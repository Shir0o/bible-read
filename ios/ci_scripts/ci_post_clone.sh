#!/bin/sh
# Xcode Cloud / CI bootstrap: materialize Flutter + CocoaPods state that
# xcodebuild needs before it resolves packages or runs build phases.
#
# The Runner target's "[CI] Bootstrap Flutter" build phase invokes this for
# plain Xcode builds; Xcode Cloud runs it automatically after cloning when it
# exists and is executable. `flutter pub get` MUST run first: it regenerates
# ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage
# (gitignored), the local Swift package Xcode resolves before any build phase.
# Without it, archives fail with:
#   Could not resolve package dependencies: ... FlutterGeneratedPluginSwiftPackage
#   doesn't exist in file system

set -e

if [ -n "${SKIP_CI_BOOTSTRAP:-}" ]; then
  echo "[CI] Flutter bootstrap: skipped (SKIP_CI_BOOTSTRAP is set)"
  exit 0
fi

# CocoaPods (Ruby) errors on non-UTF-8 locales; default when unset.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Repository root: Xcode Cloud exports CI_PRIMARY_REPOSITORY_PATH; otherwise
# derive from this script's own location (ios/ci_scripts/ci_post_clone.sh).
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] && [ -d "${CI_PRIMARY_REPOSITORY_PATH}" ]; then
  REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH}"
else
  REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
fi

# Locate the Flutter SDK: honor FLUTTER_ROOT / PATH, then common install paths.
FLUTTER_BIN=""
if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "${FLUTTER_ROOT}/bin/flutter" ]; then
  FLUTTER_BIN="${FLUTTER_ROOT}/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  for candidate in \
    "${HOME}/flutter/bin/flutter" \
    "/opt/flutter/bin/flutter" \
    "/usr/local/flutter/bin/flutter" \
    "/Volumes/workspace/flutter/bin/flutter"
  do
    if [ -x "${candidate}" ]; then
      FLUTTER_BIN="${candidate}"
      break
    fi
  done
fi

if [ -z "${FLUTTER_BIN}" ]; then
  echo "error: flutter not found. Export FLUTTER_ROOT (or add flutter to PATH) in the Xcode Cloud workflow environment." >&2
  exit 1
fi

cd "${REPO_ROOT}"
echo "[CI] Flutter bootstrap: ${FLUTTER_BIN} pub get"
"${FLUTTER_BIN}" pub get

# Remaining plugins (permission_handler_apple, vibration) still use CocoaPods;
# keep the Pods sandbox in sync when CocoaPods is available.
if [ -f "ios/Podfile" ] && command -v pod >/dev/null 2>&1; then
  echo "[CI] Flutter bootstrap: pod install"
  (cd ios && pod install)
elif [ -f "ios/Podfile" ]; then
  echo "warning: CocoaPods not found; skipping pod install. Prepare the Pods sandbox in the Xcode Cloud workflow if pods are required." >&2
fi
