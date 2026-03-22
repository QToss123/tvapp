#!/bin/bash
# Run tv_app_books for Linux (Ubuntu/WSL)
# Usage: From WSL Ubuntu, run: ./scripts/run_linux.sh
# Or: wsl -d Ubuntu-22.04 bash -c "cd /mnt/c/Users/meena/Desktop/git/tv_app_books && ./scripts/run_linux.sh"

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== tv_app_books - Linux run ==="
echo "Project: $PROJECT_DIR"
echo ""

# 1. Install Linux build dependencies (including WebKitGTK for webview_flutter)
echo ">>> Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libwebkit2gtk-4.1-dev

# 2. Setup Flutter in WSL (if not found)
FLUTTER_CMD=""
if command -v flutter &>/dev/null; then
  FLUTTER_CMD="flutter"
  echo ">>> Using existing Flutter: $(which flutter)"
else
  FLUTTER_DIR="$HOME/flutter"
  if [ ! -d "$FLUTTER_DIR/bin" ]; then
    echo ">>> Cloning Flutter for Linux (stable)..."
    mkdir -p "$HOME"
    cd "$HOME"
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    cd "$PROJECT_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
  FLUTTER_CMD="$FLUTTER_DIR/bin/flutter"
  echo ">>> Using Flutter at: $FLUTTER_DIR"
fi

# 3. Enable Linux desktop
$FLUTTER_CMD config --enable-linux-desktop

# 4. Get dependencies and run
echo ">>> Running flutter pub get..."
$FLUTTER_CMD pub get

echo ">>> Running app for Linux..."
$FLUTTER_CMD run -d linux
