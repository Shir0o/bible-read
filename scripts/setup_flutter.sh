#!/usr/bin/env bash
set -euo pipefail

# Navigate to repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

#
# Optional caching
# -----------------
#
# To speed up repeated runs, preserve the `flutter/bin/cache` and `.pub-cache`
# directories between executions. Set the following environment variables to
# point at persistent locations containing previously saved caches:
#
#   export FLUTTER_BIN_CACHE=/path/to/saved/flutter_bin_cache
#   export PUB_CACHE_SRC=/path/to/saved/pub_cache
#
# After the script completes, copy the caches back to those locations so they
# can be reused later:
#
#   rsync -a flutter/bin/cache/ "$FLUTTER_BIN_CACHE"/
#   rsync -a .pub-cache/ "$PUB_CACHE_SRC"/
#
# When present, the script restores the caches before running `flutter pub get`
# and uses `--offline` to avoid network downloads.

if [ ! -d flutter ]; then
  git clone --depth 1 https://github.com/flutter/flutter.git -b stable flutter
fi

# Restore Flutter cache if provided
if [ -n "${FLUTTER_BIN_CACHE:-}" ] && [ -d "$FLUTTER_BIN_CACHE" ] && [ ! -d flutter/bin/cache ]; then
  echo "Restoring Flutter cache from $FLUTTER_BIN_CACHE"
  mkdir -p flutter/bin
  cp -R "$FLUTTER_BIN_CACHE" flutter/bin/cache
fi

# Restore pub cache if provided
PUB_CACHE_DIR="$REPO_ROOT/.pub-cache"
if [ -n "${PUB_CACHE_SRC:-}" ] && [ -d "$PUB_CACHE_SRC" ] && [ ! -d "$PUB_CACHE_DIR" ]; then
  echo "Restoring pub cache from $PUB_CACHE_SRC"
  cp -R "$PUB_CACHE_SRC" "$PUB_CACHE_DIR"
fi
mkdir -p "$PUB_CACHE_DIR"
export PUB_CACHE="$PUB_CACHE_DIR"

export PATH="$REPO_ROOT/flutter/bin:$PATH"

flutter --version
flutter config --no-analytics &
(yes | flutter doctor --android-licenses || true) &
wait

# Use offline mode when caches already exist to skip network downloads
if [ -d flutter/bin/cache ] && [ -d "$PUB_CACHE_DIR" ]; then
  flutter pub get --offline || flutter pub get
else
  flutter pub get
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Flutter SDK installed in $REPO_ROOT/flutter"
  echo "Add it to your PATH by running:"
  echo "  export PATH=\"$REPO_ROOT/flutter/bin:\$PATH\""
fi

