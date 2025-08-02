#!/usr/bin/env bash
set -euo pipefail

# Navigate to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d flutter ]; then
  git clone https://github.com/flutter/flutter.git -b stable flutter
fi

export PATH="$REPO_ROOT/flutter/bin:$PATH"

flutter doctor
flutter config --no-analytics
yes | flutter doctor --android-licenses || true
flutter pub get

