# Build Windows installer for tv_app_books
# Requires: Flutter, Dart, Inno Setup 6
# Install Inno Setup: winget install -e --id JRSoftware.InnoSetup

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

Set-Location $ProjectRoot
Write-Host "Project root: $ProjectRoot" -ForegroundColor Cyan

# Optional: check for Inno Setup
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
    $iscc = "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path $iscc)) {
    Write-Host "Inno Setup 6 not found. Install it first:" -ForegroundColor Yellow
    Write-Host "  winget install -e --id JRSoftware.InnoSetup" -ForegroundColor Yellow
    Write-Host "Then re-run this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n1. Running flutter pub get..." -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n2. Building Windows installer (flutter build windows + Inno Setup)..." -ForegroundColor Green
dart run inno_bundle
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nDone. The installer .exe is under build\ (see inno_bundle output above)." -ForegroundColor Green
