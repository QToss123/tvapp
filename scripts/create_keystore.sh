#!/usr/bin/env bash
# Create a new upload keystore and android/key.properties for signed release APK.
# Run from project root: ./scripts/create_keystore.sh
# You will be prompted for passwords; keep them safe.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"
KEYSTORE_FILE="$ANDROID_DIR/upload-keystore.jks"
PROPS_FILE="$ANDROID_DIR/key.properties"

cd "$PROJECT_ROOT"

echo "=== Create keystore for signed release APK ==="
echo ""

if [[ -f "$KEYSTORE_FILE" ]]; then
  echo "Keystore already exists: $KEYSTORE_FILE"
  read -p "Overwrite? (y/N): " overwrite
  if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
  rm -f "$KEYSTORE_FILE"
fi

echo "Creating keystore (valid 10000 days). You will be asked for a keystore password and key password."
keytool -genkey -v -keystore "$KEYSTORE_FILE" -keyalg RSA -keysize 2048 -validity 10000 -alias upload

echo ""
echo "Creating key.properties (use the same passwords you just set)."
read -sp "storePassword: " STORE_PW
echo ""
read -sp "keyPassword: " KEY_PW
echo ""

cat > "$PROPS_FILE" << EOF
storePassword=$STORE_PW
keyPassword=$KEY_PW
keyAlias=upload
storeFile=upload-keystore.jks
EOF

echo ""
echo "Done."
echo "  Keystore: $KEYSTORE_FILE"
echo "  Config:   $PROPS_FILE"
echo ""
echo "Build signed APK: flutter build apk --release"
echo "Output: build/app/outputs/flutter-apk/app-release.apk"
