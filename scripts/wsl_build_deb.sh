#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
# Install Flutter if missing (to home dir of current user)
if ! command -v flutter &>/dev/null; then
  FLUTTER_DIR="${HOME}/flutter"
  if [ ! -f "$FLUTTER_DIR/bin/flutter" ]; then
    echo ">>> Installing Flutter in WSL..."
    mkdir -p "$HOME" && cd "$HOME"
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    cd "$PROJECT_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi
# Install build deps
echo ">>> Ensuring build dependencies..."
sudo apt-get update -qq 2>/dev/null || true
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libwebkit2gtk-4.1-dev 2>/dev/null || true
# Build
sed -i 's/\r$//' scripts/build_linux_installer.sh 2>/dev/null || true
bash scripts/build_linux_installer.sh
