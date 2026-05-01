#!/usr/bin/env bash
# Capture App Store / Play Store screenshots across the three Play form factors:
# phone, 7" tablet, 10" tablet. Outputs PNGs into screenshots-<form-factor>/.
#
# Usage:
#   scripts/capture_play_store.sh                       # uses defaults below
#   PHONE_AVD=Pixel_8 scripts/capture_play_store.sh
#
# Pre-req: the named AVDs exist (see `flutter emulators`). Create missing ones
# in Android Studio's Device Manager.

set -euo pipefail

PHONE_AVD="${PHONE_AVD:-Small_Phone}"
TABLET7_AVD="${TABLET7_AVD:-Nexus_7}"
TABLET10_AVD="${TABLET10_AVD:-Pixel_Tablet}"

TESTS=(
  integration_test/main_flow_test.dart
  integration_test/home_page_mark_as_read_test.dart
  integration_test/streak_validation_test.dart
  integration_test/bible_mastery_achievement_test.dart
  integration_test/seasonal_challenge_journey_test.dart
  integration_test/social_engagement_journey_test.dart
  integration_test/group_collaboration_journey_test.dart
  integration_test/friendship_social_journey_test.dart
)

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

wait_for_device() {
  echo "Waiting for emulator to boot..."
  # Wait until at least one emulator-* serial appears in `adb devices`.
  until adb devices | awk '/^emulator-[0-9]+\s+device$/{found=1} END{exit !found}'; do
    sleep 2
  done
  local serial
  serial="$(adb devices | awk '/^emulator-[0-9]+\s+device$/{print $1; exit}')"
  until [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 2
  done
  echo "Emulator $serial booted."
  echo "$serial"
}

stop_emulators() {
  adb devices | awk '/emulator-/{print $1}' | while read -r d; do
    adb -s "$d" emu kill || true
  done
  sleep 3
}

capture_for_device() {
  local avd="$1" out_dir="$2"

  echo
  echo "==> Booting $avd"
  stop_emulators
  flutter emulators --launch "$avd"
  local serial
  serial="$(wait_for_device | tail -n1)"

  rm -f screenshots/*.png
  for t in "${TESTS[@]}"; do
    echo "--- $t on $avd ($serial)"
    flutter drive -d "$serial" --driver=test_driver/screenshot_driver.dart --target="$t"
  done

  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.png
  mv screenshots/*.png "$out_dir"/
  echo "==> $out_dir/ has $(ls "$out_dir"/*.png 2>/dev/null | wc -l | tr -d ' ') PNGs"
}

capture_for_device "$PHONE_AVD"    screenshots/phone
capture_for_device "$TABLET7_AVD"  screenshots/tablet_7
capture_for_device "$TABLET10_AVD" screenshots/tablet_10

stop_emulators
echo
echo "Done. Upload contents of:"
echo "  screenshots/phone/     -> Play Console: Phone"
echo "  screenshots/tablet_7/  -> Play Console: 7-inch tablet"
echo "  screenshots/tablet_10/ -> Play Console: 10-inch tablet"
