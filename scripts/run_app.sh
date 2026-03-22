#!/usr/bin/env bash
# Run the app in one command. Uses first available device (Android phone, emulator, Chrome, or macOS).
# Usage: ./scripts/run_app.sh
# Or with a specific device: ./scripts/run_app.sh android  |  ./scripts/run_app.sh chrome

set -e
cd "$(dirname "$0")/.."

echo "=== Running BurlingtonEnglish ==="
flutter pub get

if [[ -n "$1" ]]; then
  case "$1" in
    android) flutter run -d android ;;
    chrome)  flutter run -d chrome ;;
    macos)   flutter run -d macos ;;
    *)       flutter run -d "$1" ;;
  esac
else
  flutter run
fi
