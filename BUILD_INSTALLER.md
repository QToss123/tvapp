# Building the Windows installer

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
