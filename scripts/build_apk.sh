#!/usr/bin/env bash
# Build Android release APK for tv_app_books.
# Run from project root: ./scripts/build_apk.sh

set -e
cd "$(dirname "$0")/.."

echo "=== Building Android release APK ==="
echo "Project: $(pwd)"
echo ""

echo "1. Running flutter pub get..."
flutter pub get

echo ""
echo "2. Building release APK..."
flutter build apk --release

echo ""
echo "=== Done ==="
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
ls -la build/app/outputs/flutter-apk/app-release.apk 2>/dev/null || true
