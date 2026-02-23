# MSI / Windows installer notes

## Advanced Installer: app stuck on "Opening book" screen

If the app works when you run the **EXE directly** from the build folder but **stops responding** after opening a book when installed via **Advanced Installer** (or another MSI), the shortcut is likely starting the app with the wrong **working directory**.

### Fix: Set the shortcut "Start in" (working directory)

1. In **Advanced Installer**, open your project.
2. Go to **Shortcuts** (or **Installation** → **Shortcuts**).
3. Open the shortcut that launches **tv_app_books.exe** (e.g. Desktop or Start Menu).
4. Set **"Start in"** / **Working directory** to the **application install folder**, for example:
   - `[INSTALLDIR]`  
   - or `[ProgramFilesFolder]BurlingtonEnglish`  
   (Use the same folder where **tv_app_books.exe** is installed.)
5. Rebuild the MSI and reinstall.

The app and its DLLs must run with that folder as the current directory. If "Start in" is empty or wrong, the process can fail to load correctly or hang when opening a book.

### Also check

- **Install for**: "All users" or "Current user" is fine, but the shortcut must **Run as user** (not elevated).
- **Target**: Should be `[INSTALLDIR]tv_app_books.exe` (or your exe name).

---

## Creating installers from the command line

### Option 1: Inno Setup (EXE installer) – already in this project

Produces an **.exe** installer (not .msi). Shortcuts get the correct "Start in" so the app works.

1. **Build the Windows release first:**
   ```powershell
   cd c:\Users\meena\Desktop\git\tv_app_books
   flutter build windows --release
   ```

2. **Install Inno Setup** (if not installed):
   ```powershell
   winget install -e --id JRSoftware.InnoSetup
   ```

3. **Build the installer** (either way):

   **A) Using inno_bundle (Flutter):**
   ```powershell
   dart run inno_bundle
   ```
   Output is usually in `build\windows\x64\runner\` or project root (see console).

   **B) Using Inno Setup compiler directly:**
   ```powershell
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\MyFlutterApp.iss
   ```
   Output: `windows\Output\BurlingtonEnglishSetup.exe` (or path shown in the script).

### Option 2: Real MSI from the command line

- **WiX Toolset** (free): Install WiX, author a .wxs file, then build with `candle` and `light` (or MSBuild). Produces a real .msi.
- **Advanced Installer CLI**: If you use Advanced Installer, you can build from command line, e.g.:
  ```powershell
  "C:\Program Files (x86)\Caphyon\Advanced Installer\bin\x86\AdvancedInstaller.com" /build "path\to\your.aip"
  ```
  (Path depends on your Advanced Installer install.)

---

## Faster book opening

Book opening can feel slow when using the MSI-installed app. Here are the main causes and what to do:

### 1. First open of each book is slower
- The first time you open a book, it must **decrypt** (if encrypted) and **extract** the ZIP to temp. This is unavoidable.
- **Second and later opens** of the same book reuse the extracted cache, so they are much faster.

### 2. Windows Defender / antivirus can slow file access
When the app runs from Program Files, antivirus may scan every file read/write (decrypt, extract, serve). That can add noticeable delay.

**Tip:** Add Windows Defender exclusions for faster opening:
1. Open **Windows Security** → **Virus & threat protection** → **Manage settings** (under Virus & threat protection settings) → **Exclusions** → **Add or remove exclusions** → **Add an exclusion** → **Folder**.
2. Add these folders (adjust paths for your setup):
   - `C:\Program Files\BurlingtonEnglish` (app install folder)
   - `C:\Users\<YourUser>\AppData\Local\Temp\extracted_books` (book extract cache)
   - `C:\Users\<YourUser>\AppData\Local\Temp\decrypted_books` (decrypted cache)

Or add your **book storage folder** if books are in a custom location.

### 3. Books on slow drives
- If books are on an external USB drive or network share, reading and decrypting them will be slower.
- Storing books on a fast local drive (e.g. SSD) improves first-open time.

### 4. What the app does to help
- Keeps extracted books in cache so **reopening the same book is fast**.
- Runs decrypt/extract off the main thread so the UI stays responsive.
- Uses parallel work (file check, DB lookup, settings) where possible.
