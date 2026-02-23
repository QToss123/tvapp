# Build Windows MSI installer for tv_app_books
# Requires: Flutter, WiX Toolset (dotnet tool install -g wix)
# Install WiX: dotnet tool install -g wix

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

Set-Location $ProjectRoot
Write-Host "Project root: $ProjectRoot" -ForegroundColor Cyan

# 1. Flutter build
Write-Host "`n1. Running flutter pub get..." -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n2. Building Flutter Windows release..." -ForegroundColor Green
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 2. Find Release directory (Flutter may use x64 subfolder)
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    $ReleaseDir = Join-Path $ProjectRoot "build\windows\runner\Release"
}
if (-not (Test-Path $ReleaseDir)) {
    Write-Host "Error: Release directory not found. Expected at:" -ForegroundColor Red
    Write-Host "  build\windows\x64\runner\Release" -ForegroundColor Red
    Write-Host "  or build\windows\runner\Release" -ForegroundColor Red
    exit 1
}
Write-Host "Release dir: $ReleaseDir" -ForegroundColor Cyan

# 3. Check WiX
$wix = Get-Command wix -ErrorAction SilentlyContinue
if (-not $wix) {
    Write-Host "WiX not found. Install it first:" -ForegroundColor Yellow
    Write-Host "  dotnet tool install -g wix" -ForegroundColor Yellow
    Write-Host "Then re-run this script." -ForegroundColor Yellow
    exit 1
}

# 4. Build MSI
Write-Host "`n3. Building MSI installer..." -ForegroundColor Green
$InstallerDir = Join-Path $ProjectRoot "installer"
$OutputDir = Join-Path $ProjectRoot "build"
Set-Location $InstallerDir
wix build Product.wxs -arch x64 -bindpath Release="$ReleaseDir" -o "$OutputDir\BurlingtonEnglish.msi"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $ProjectRoot
Write-Host "`nDone. MSI installer: build\BurlingtonEnglish.msi" -ForegroundColor Green
