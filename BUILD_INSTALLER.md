# Building installers and release APK

## Android release APK

Build a release APK for Android / Android TV.

### Prerequisites

1. **Flutter** – [Get Flutter](https://docs.flutter.dev/get-started/install)
2. **Android SDK** – Install via [Android Studio](https://developer.android.com/studio) or command-line tools
3. **Environment**
   - Run as your **normal user** (not root). Root can cause Gradle cache/permission issues.
   - If Flutter is installed via Homebrew, fix SDK permissions once:
     ```bash
     sudo chown -R $(whoami):staff /opt/homebrew/share/flutter/packages/flutter_tools/gradle
     ```
   - Ensure enough **free disk space** (several GB for Gradle caches and build output).

### Build the release APK

From the project root:

**macOS / Linux:**
```bash
./scripts/build_apk.sh
```

**Or manually:**
```bash
flutter pub get
flutter build apk --release
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

### Signed release APK (generate signed APK)

**Option A – Create keystore and build (recommended)**

1. Create a new keystore and `android/key.properties` (you will be prompted for passwords):
   ```bash
   ./scripts/create_keystore.sh
   ```
2. Build the signed release APK:
   ```bash
   flutter build apk --release
   ```
   Or: `./scripts/build_apk.sh`

**Option B – Use an existing keystore**

1. Put your `.jks` or `.keystore` file in `android/` (e.g. `android/upload-keystore.jks`).
2. Create `android/key.properties` with **relative** path so it works on any machine:
   ```properties
   storePassword=your_store_password
   keyPassword=your_key_password
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
3. Run `flutter build apk --release` (or `./scripts/build_apk.sh`).

**Output:** `build/app/outputs/flutter-apk/app-release.apk` (signed with your key).

If `key.properties` is missing or `storeFile` does not exist, the release build uses the **debug** keystore (fine for sideloading, not for Play Store).

### Release build: storage not loading / file missing

If in **release** the storage list doesn’t load or you see “file missing” when opening books:

- **Minification is disabled** in `android/app/build.gradle.kts` for the release build (`isMinifyEnabled = false`, `isShrinkResources = false`) so SharedPreferences, path_provider, and file I/O are not stripped.
- **ProGuard rules** in `android/app/proguard-rules.pro` keep Flutter, SharedPreferences, and path_provider classes if you turn minification back on later.

Rebuild the release APK after these changes. If problems persist, ensure the device has storage permission (“All files access” on Android 11+) and that the chosen storage path exists.

---

## Windows installer

This project supports two Windows installer formats:

1. **MSI** – WiX Toolset (recommended for enterprise deployment)
2. **EXE** – Inno Setup via [inno_bundle](https://pub.dev/packages/inno_bundle)

---

## MSI installer (WiX)

Creates a `.msi` package suitable for enterprise deployment, Group Policy, and silent installs.

### Prerequisites

1. **Flutter** – [Get Flutter](https://docs.flutter.dev/get-started/install)
2. **WiX Toolset** – Install the `wix` dotnet tool:
   ```powershell
   dotnet tool install -g wix
   ```

### Build the MSI

From the project root:

```powershell
.\scripts\build_msi.ps1
```

The script will:

1. Run `flutter pub get` and `flutter build windows --release`
2. Build the MSI using WiX with the Release output
3. Write `build\TVAppBooks.msi`

### MSI configuration

- **Product.wxs** – WiX source in `installer/Product.wxs` (version, shortcuts, upgrade code)
- **UpgradeCode** – Do not change after release (used for upgrades/uninstalls)

---

## EXE installer (Inno Setup)

Creates a `.exe` installer using Inno Setup.

### Prerequisites

1. **Flutter** – [Get Flutter](https://docs.flutter.dev/get-started/install)
2. **Inno Setup 6** – Install via:
   ```powershell
   winget install -e --id JRSoftware.InnoSetup
   ```
   Or download from [jrsoftware.org](https://jrsoftware.org/isinfo.php).

### Build the EXE

From the project root:

```powershell
.\scripts\build_installer.ps1
```

Or manually:

```powershell
flutter pub get
dart run inno_bundle
```

`inno_bundle` runs `flutter build windows` and then packages the output with Inno Setup. The installer `.exe` is written under `build/` (exact path is printed by `inno_bundle`).

### Configuration

Installer options are in `pubspec.yaml` under `inno_bundle`:

- **id** – AppId (GUID). Do not change after release.
- **name** – Display name (e.g. "BurlingtonEnglish").
- **installer_icon** – `.ico` used for the installer.
- **admin** – `false` = user install, `true` = machine-wide, `auto` = user choice.

See [inno_bundle Configuration Options](https://github.com/hahouari/inno_bundle/wiki/Configuration-Options) for more.

## Troubleshooting

- **Inno Setup not found** – Install Inno Setup 6 and ensure it’s on `PATH`, or use the default install path.
- **WiX not found** – Run `dotnet tool install -g wix` and ensure `dotnet` tools are on `PATH`.
- **MSB3073 / build errors** – If you use `webview_win_floating`, try running the build in an **elevated** (Administrator) terminal.
- **VC++ Redist** – The installer can bundle or prompt for Visual C++ Redistributable. Use `vc_redist` in `inno_bundle` config if needed.
