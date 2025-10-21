#!/bin/sh
set -euxo pipefail

# ====== Config ======
FLUTTER_VERSION=3.24.3

# ====== Install Flutter (cached per build machine, fresh per new VM) ======
if [ ! -d "$PWD/flutter" ]; then
  git clone -b $FLUTTER_VERSION https://github.com/flutter/flutter.git --depth 1
fi
export PATH="$PWD/flutter/bin:$PATH"

# Show versions for logs
flutter --version
dart --version

# ====== Flutter deps ======
flutter pub get

# ====== iOS deps (CocoaPods) ======
cd ios

# Avoid slow Pod repo updates unless needed; fallback if first install fails
if ! pod install; then
  pod repo update
  pod install
fi
