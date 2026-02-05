# 1. Install Linux dependencies required by Flutter
sudo apt-get update
sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa libgtk-3-dev mesa-utils

# 2. Download the Flutter SDK into the home directory
cd /home/jules
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi

# 3. Add Flutter to the PATH
export PATH="$PATH:/home/jules/flutter/bin"

# 4. Pre-download Flutter artifacts and verify setup
flutter precache
flutter doctor -v

# 5. Install project dependencies
flutter pub get