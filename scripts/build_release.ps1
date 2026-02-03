# Build release for tv_app_books (Windows + Android)
# Run from project root: .\scripts\build_release.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

Set-Location $ProjectRoot
Write-Host "=== Building release for BurlingtonEnglish ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot" -ForegroundColor Cyan
Write-Host ""

# Find Flutter (PATH or common location)
$Flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $Flutter) {
    $FlutterPath = "C:\src\flutter\bin\flutter.bat"
    if (Test-Path $FlutterPath) {
        $Flutter = $FlutterPath
        Write-Host "Using Flutter at: $FlutterPath" -ForegroundColor Yellow
    } else {
        Write-Host "Error: Flutter not found. Add Flutter to PATH or install at C:\src\flutter" -ForegroundColor Red
        exit 1
    }
} else {
    $Flutter = "flutter"
}

# 1. Pub get
Write-Host "1. Running flutter pub get..." -ForegroundColor Green
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 2. Windows release
Write-Host "`n2. Building Windows release..." -ForegroundColor Green
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 3. Android release (APK)
Write-Host "`n3. Building Android release (APK)..." -ForegroundColor Green
& $Flutter build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Windows: build\windows\x64\runner\Release\" -ForegroundColor Cyan
Write-Host "Android: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
