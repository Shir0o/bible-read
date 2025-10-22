#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP="${REPO_ROOT}/ci_scripts/ci_post_clone.sh"

echo "ci_pre_xcodebuild: intentionally failing to verify Xcode Cloud integration."
exit 1

if [ -x "${BOOTSTRAP}" ]; then
  IOS_INPUT_LIST="${REPO_ROOT}/ios/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-input-files.xcfilelist"
  GENERATED_CONFIG="${REPO_ROOT}/ios/Flutter/Generated.xcconfig"

  if [ -f "${IOS_INPUT_LIST}" ] && [ -f "${GENERATED_CONFIG}" ]; then
    echo "Skipping Flutter bootstrap: existing iOS artifacts detected."
    exit 0
  fi

  echo "Running ${BOOTSTRAP} to prepare Flutter and CocoaPods dependencies..."
  (cd "${REPO_ROOT}" && bash "${BOOTSTRAP}")
else
  echo "warning: Expected bootstrap script ${BOOTSTRAP} not found or not executable." >&2
fi
