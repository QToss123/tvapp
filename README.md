# TV App Books (Linux)

**Burlington – Bookshelf App** – A Flutter app for reading books on Linux. Supports EPUB and other formats with sync capabilities.

---

## Prerequisites

- **Ubuntu** (or Debian-based Linux)
- **Flutter** – [Get Flutter](https://docs.flutter.dev/get-started/install/linux) (use manual install, not snap)
- **Build dependencies:**
  ```bash
  sudo apt-get update
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libwebkit2gtk-4.1-dev
  ```

---

## Run the app

```bash
cd /path/to/tv_app_books
bash scripts/run_linux.sh
```

First run installs Flutter and dependencies if needed. Enter your sudo password when prompted.

---

## Build .deb installer

```bash
cd /path/to/tv_app_books
rm -rf build/linux   # if you moved the project, clear old cache
bash scripts/build_linux_installer.sh
```

**Output:** `build/tv-app-books_1.0.0_amd64.deb`

---

## Install the .deb

```bash
sudo dpkg -i build/tv-app-books_1.0.0_amd64.deb
sudo apt-get install -f
```

**Run the app:**
```bash
tv_app_books
```
Or launch **TV App Books** from the application menu.

---

## Uninstall

```bash
sudo apt remove tv-app-books
```

---

## WSL (Windows Subsystem for Linux)

To build from Windows using WSL:

1. Install Ubuntu via WSL: `wsl --install -d Ubuntu`
2. From PowerShell: `.\scripts\build_linux.ps1`
3. Or in WSL: `cd /mnt/c/Users/.../tv_app_books` then `bash scripts/build_linux_installer.sh`

**Tip:** Copy the project to `~/tv_app_books` for faster builds (native Linux filesystem):
```bash
cp -r /mnt/c/Users/meena/Desktop/git/tv_app_books ~/
cd ~/tv_app_books
```

See [LINUX_BUILD.md](LINUX_BUILD.md) for detailed WSL setup and troubleshooting.
