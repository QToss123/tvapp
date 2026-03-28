#!/usr/bin/env bash
# Unified release build helper for Linux host:
# - Android APK
# - Linux .deb
#
# Windows artifacts must be built on Windows host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter is not installed or not in PATH."
  exit 1
fi

echo "=== Unified release build (Linux host) ==="
echo "Project: $PROJECT_DIR"
echo ""

echo "1) flutter pub get"
flutter pub get

echo ""
echo "2) Android APK release"
bash "$SCRIPT_DIR/build_apk.sh"

echo ""
echo "3) Linux .deb package"
bash "$SCRIPT_DIR/build_linux_installer.sh"

echo ""
echo "=== Linux host builds complete ==="
echo "APK : build/app/outputs/flutter-apk/app-release.apk"
echo "DEB : build/*.deb"
echo ""
echo "Windows build note:"
echo "Run on Windows host: powershell -ExecutionPolicy Bypass -File .\\scripts\\build_release.ps1"
