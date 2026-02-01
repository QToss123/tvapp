#!/bin/bash
# Build Ubuntu/Debian .deb installer for tv_app_books
# Run from project root, or: bash scripts/build_linux_installer.sh
# Requires: Flutter (manual install, not snap), dpkg-deb, libwebkit2gtk-4.1-dev

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="tv_app_books"
PACKAGE_NAME="tv-app-books"
APP_DISPLAY="TV App Books"
APP_ID="com.liqvid.tv_app_books"
# Read version from pubspec.yaml (e.g. 1.0.0+1 -> 1.0.0)
VERSION=$(grep -E '^version:' pubspec.yaml | sed 's/version: *\([0-9.]*\).*/\1/')
ARCH="amd64"
DEB_DIR="$PROJECT_DIR/build/linux_deb"
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"

echo "=== Building Ubuntu installer for $APP_DISPLAY ==="
echo "Project: $PROJECT_DIR"
echo ""

# 1. Build Flutter Linux release
echo ">>> Building Flutter Linux release..."
flutter pub get
flutter build linux --release

if [ ! -f "$BUNDLE_DIR/$APP_NAME" ]; then
  echo "Error: Build output not found at $BUNDLE_DIR/$APP_NAME"
  exit 1
fi

# 2. Create .deb package structure
echo ">>> Creating .deb package structure..."
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/opt/$APP_NAME"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy app bundle to /opt
cp -r "$BUNDLE_DIR"/* "$DEB_DIR/opt/$APP_NAME/"

# Launcher script (runs from app dir so lib/ and data/ resolve correctly)
cat > "$DEB_DIR/usr/bin/$APP_NAME" << 'LAUNCHER'
#!/bin/bash
exec /opt/tv_app_books/tv_app_books "$@"
LAUNCHER
chmod 755 "$DEB_DIR/usr/bin/$APP_NAME"

# .desktop file for app menu
cat > "$DEB_DIR/usr/share/applications/$APP_ID.desktop" << DESKTOP
[Desktop Entry]
Name=TV App Books
Comment=Burlington - Bookshelf App
Exec=/opt/tv_app_books/tv_app_books
Icon=$APP_ID
Type=Application
Categories=Office;Viewer;
StartupNotify=true
DESKTOP

# Copy icon
if [ -f "$PROJECT_DIR/web/icons/Icon-512.png" ]; then
  cp "$PROJECT_DIR/web/icons/Icon-512.png" "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
fi

# DEBIAN/control (Package name must be lowercase alphanumeric + -+. only)
cat > "$DEB_DIR/DEBIAN/control" << CONTROL
Package: $PACKAGE_NAME
Version: $VERSION
Section: office
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0, libblkid1, liblzma5, libwebkit2gtk-4.1-0
Maintainer: TV App Books <noreply@example.com>
Description: Burlington - Bookshelf App
 A Flutter app for reading books on Android, Windows, and Linux.
 .
 Supports EPUB and other book formats with sync capabilities.
CONTROL

# Strip CRLF from control file (can occur when script has Windows line endings)
sed -i 's/\r$//' "$DEB_DIR/DEBIAN/control"

# Fix permissions (dpkg-deb requires DEBIAN 0755-0775, not 777; common on WSL/mounted drives)
chmod 755 "$DEB_DIR"
chmod 755 "$DEB_DIR/DEBIAN"
chmod 644 "$DEB_DIR/DEBIAN/control"

# 3. Build .deb (fakeroot for correct file ownership)
echo ">>> Building .deb package..."
if command -v fakeroot &>/dev/null; then
  fakeroot dpkg-deb -b "$DEB_DIR" "$PROJECT_DIR/build/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
else
  dpkg-deb --build --root-owner-group "$DEB_DIR" "$PROJECT_DIR/build/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb" 2>/dev/null || dpkg-deb -b "$DEB_DIR" "$PROJECT_DIR/build/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
fi

echo ""
echo "=== Done ==="
echo "Installer: $PROJECT_DIR/build/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "To install: sudo dpkg -i build/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
echo "To fix missing deps: sudo apt-get install -f"
