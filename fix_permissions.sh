#!/bin/bash
# Fix permission denied for .dart_tool, build, and Gradle cache (owned by root)
# Run from project root in Terminal: bash fix_permissions.sh
# You will be prompted for your Mac password.

cd "$(dirname "$0")"
echo "Fixing permissions in $(pwd)..."

# 1. Fix ownership of entire project (you'll be prompted for password)
echo "Changing ownership of project directory..."
sudo chown -R $(whoami):staff .

# 2. Fix Gradle cache if needed (for device_info_plus / transforms errors)
if [ -d "$HOME/.gradle/caches/8.14/transforms" ]; then
  echo "Clearing Gradle transforms cache..."
  rm -rf "$HOME/.gradle/caches/8.14/transforms"
fi

# 3. Clean and get deps
echo "Running flutter clean..."
flutter clean
echo "Running flutter pub get..."
flutter pub get

echo "Done! Run: flutter build apk --release"
