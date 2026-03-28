# Release Build Matrix

This branch supports Android APK, Linux `.deb`, and Windows release artifacts from a unified workflow.

## Prerequisites
- Flutter SDK in `PATH`
- Project dependencies restored with `flutter pub get`

Platform extras:
- Linux `.deb`: `dpkg-deb` (and `fakeroot` recommended)
- Windows installer: Inno Setup 6 (`ISCC.exe`)
- Android signing: existing keystore/signing setup for release

## Linux Host (APK + DEB)
Run both deliverables from Linux:

```bash
bash scripts/build_unified_release.sh
```

Outputs:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- DEB: `build/<package>_<version>_amd64.deb`

## Android APK Only

```bash
bash scripts/build_apk.sh
```

## Linux DEB Only

```bash
bash scripts/build_linux_installer.sh
```

## Docker Linux (Dev / Prod)

Reproducible Linux builds in a container; outputs **`app-release_Dev.deb`** and **`app-release_Prod.deb`** (plus matching `linux-bundle_*` folders). See **[DOCKER_LINUX.md](../DOCKER_LINUX.md)** for full commands and `docker cp` steps.

## Windows Host (Windows + APK)
Run from PowerShell on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
```

For Windows installer `.exe`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1
```

## Validation Checklist
- [ ] Android APK generated and installs
- [ ] Linux `.deb` installs with `dpkg -i`
- [ ] Windows release folder generated
- [ ] Windows installer generated (if required)

