#!/usr/bin/env bash
set -euo pipefail

# Navigate to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d flutter ]; then
  git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
fi

export PATH="$REPO_ROOT/flutter/bin:$PATH"

flutter doctor
flutter config --no-analytics
yes | flutter doctor --android-licenses || true
flutter pub get

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Flutter SDK installed in $REPO_ROOT/flutter"
  echo "Add it to your PATH by running:"
  echo "  export PATH=\"$REPO_ROOT/flutter/bin:\$PATH\""
fi

