#!/bin/bash
# Fix permission denied for .dart_tool and build (owned by root)
# Run from project root in Terminal: bash fix_permissions.sh
# You will be prompted for your Mac password.

cd "$(dirname "$0")"
echo "Fixing permissions in $(pwd)..."

# 1. Fix ownership (you'll be prompted for password)
echo "Changing ownership of .dart_tool and build..."
sudo chown -R $(whoami):staff .dart_tool build

# 2. Also fix ios/macos/linux/windows ephemeral dirs if they're root-owned
for d in ios/Flutter/ephemeral macos/Flutter/ephemeral linux/flutter/ephemeral windows/flutter/ephemeral; do
  [ -d "$d" ] && sudo chown -R $(whoami):staff "$d" 2>/dev/null
done

# 3. Clean and get deps
echo "Running flutter clean..."
flutter clean
echo "Running flutter pub get..."
flutter pub get

echo "Done! Run: flutter run -d emulator-5554"
