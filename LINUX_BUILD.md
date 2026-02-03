# Linux (Ubuntu) build

Flutter’s **Linux build runs only on a Linux host**. On Windows, use **WSL (Ubuntu)** or an Ubuntu machine/VM.

---

**Important:** Do **not** install Flutter via `apt` or `snap` when using webview_win_floating—it causes glibc conflicts with webkit2gtk. Use the manual Flutter install (clone from GitHub) instead.

## How to reach the Ubuntu (WSL) prompt `user@machine:~$`

You need to be in **Ubuntu**, not PowerShell. Use one of these:

### Option A: Open Ubuntu from Start menu
1. Click the **Start** button (or press the Windows key).
2. Type **`Ubuntu`**.
3. Click **"Ubuntu"** (or "Ubuntu 22.04" / "Ubuntu 24.04").
4. A terminal opens. The prompt should look like **`yourname@PCNAME:~$`** (not `PS C:\...>`).  
   You are now in WSL.

### Option B: From PowerShell or Command Prompt
1. Open PowerShell or Command Prompt.
2. Type **`wsl`** and press **Enter**.
3. The prompt changes to **`yourname@PCNAME:~$`**.  
   You are now in WSL.

### Option C: From Windows Terminal
1. Open **Windows Terminal**.
2. Click the **▼** (dropdown) next to the tab, or open a new tab (Ctrl+Shift+T) and choose **Ubuntu**.
3. The prompt shows **`yourname@PCNAME:~$`**.

**If you don't have Ubuntu/WSL yet:** In PowerShell (as Administrator) run `wsl --install -d Ubuntu`, restart if asked, then finish Ubuntu setup. After that, use Option A or B above.

---

## Important: `/mnt` and Linux paths do not work in PowerShell

If you see **`PS C:\...>`** you are in **PowerShell (Windows)**. Paths like `/mnt`, `/mnt/c/...` do not exist there—Windows has no `C:\mnt`. You will get “Cannot find path 'C:\mnt'”.

- **To build for Linux:** open **Ubuntu** (WSL) and run the commands there.
- **To build for Windows:** stay in PowerShell and use `cd C:\Users\meena\Desktop\git\tv_app_books` and `flutter build windows`.

---

## On Windows: use WSL and run these inside Ubuntu

### Build Linux from PowerShell (recommended)

From the project root in **PowerShell**:

```powershell
.\scripts\build_linux.ps1
```

This invokes WSL and builds the Linux release + `.deb` installer. Requires WSL with Ubuntu installed. First time: run `run_linux.sh` in WSL once to install Flutter and dependencies.

### Quick run (one script)

1. **Start Ubuntu (WSL)** — Open **"Ubuntu"** from Start, or run `wsl` in PowerShell.
2. **Run the script** (installs deps + Flutter if needed, then runs the app):
   ```bash
   cd /mnt/c/Users/meena/Desktop/git/tv_app_books
   bash scripts/run_linux.sh
   ```
   Enter your sudo password when prompted. First run may take several minutes (apt + Flutter clone).

### Manual steps

1. **Start Ubuntu (WSL)**  
   Open **“Ubuntu”** from the Start menu (or type `Ubuntu` in the search bar).  
   Or in PowerShell run: `wsl` — that switches you into WSL. You should see a prompt like `user@machine:~$`, not `PS C:\...>`.

2. **Go to the project (WSL path)**  
   In the **Ubuntu** terminal (or after `wsl`):
   ```bash
   cd /mnt/c/Users/meena/Desktop/git/tv_app_books
   ```
   (`/mnt/c/...` is how WSL sees your Windows `C:\...`.)

3. **Install Flutter and dependencies (once)**  
   See: https://docs.flutter.dev/get-started/install/linux  
   Ubuntu packages:
   ```bash
   sudo apt-get update
   sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libwebkit2gtk-4.1-dev
   ```

4. **Build**  
   In the **Ubuntu** terminal, in the project folder:
   ```bash
   flutter build linux
   ```

5. **Output**  
   `build/linux/x64/release/` (or `build/linux/arm64/release/` on ARM).

---

## CRLF / line ending errors

If you see `$'\r': command not found` or `command not found "get"`, the shell scripts have Windows line endings (CRLF). Fix in WSL:

```bash
sed -i 's/\r$//' scripts/build_linux_installer.sh scripts/run_linux.sh
```

Then run the build again. The `build_linux.ps1` script does this automatically.

---

## Do not run the WSL path in PowerShell

The path `/mnt/c/Users/meena/Desktop/git/tv_app_books` is for **Linux/WSL only**.

In **PowerShell** (`PS C:\...>`) you are on Windows:
- Use Windows paths: `cd C:\Users\meena\Desktop\git\tv_app_books`
- Use `flutter build windows` for a Windows build
- To run a Linux build from PowerShell, **enter WSL first**: type `wsl` and press Enter, then run the `cd /mnt/c/...` and `flutter build linux` commands in the WSL prompt.

---

## On a real Ubuntu machine

Use your project path on that machine, then:

```bash
cd /path/to/tv_app_books
flutter build linux
```

Same dependencies as above if Flutter or GTK are not yet installed.

---

## Create Ubuntu installer (.deb)

To build a `.deb` package for distribution:

1. **In Ubuntu (or WSL)** — ensure Flutter (manual install) and build deps are set up.
2. **Run the installer script:**
   ```bash
   cd /mnt/c/Users/meena/Desktop/git/tv_app_books
   bash scripts/build_linux_installer.sh
   ```
3. **Output** — `build/burlingtonenglish_1.0.0_amd64.deb` (version from `pubspec.yaml`).

**Install on another Ubuntu machine:**
```bash
sudo dpkg -i burlingtonenglish_1.0.0_amd64.deb
sudo apt-get install -f   # fix any missing dependencies
```

**User dependencies** (installed automatically if missing): `libgtk-3-0`, `libwebkit2gtk-4.1-0`, `libblkid1`, `liblzma5`.
