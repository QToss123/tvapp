# Build Linux release and .deb installer for tv_app_books
# Runs in WSL (Ubuntu). Requires: WSL with Ubuntu installed.
# First run: Use run_linux.sh once to install Flutter and deps in WSL.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

# Convert Windows path to WSL path: C:\Users\... -> /mnt/c/Users/...
$drive = $ProjectRoot.Substring(0, 1).ToLower()
$pathPart = $ProjectRoot.Substring(3) -replace '\\', '/'
$WslPath = "/mnt/$drive/$pathPart"

Write-Host "=== Building Linux release for TV App Books ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot" -ForegroundColor Cyan
Write-Host "WSL path: $WslPath" -ForegroundColor Cyan
Write-Host ""

# Check WSL
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "Error: WSL not found. Install Ubuntu via: wsl --install -d Ubuntu" -ForegroundColor Red
    exit 1
}

# Fix CRLF line endings in shell scripts (Windows can add \r)
$cmd = "cd '$WslPath' && sed -i 's/\r$//' scripts/build_linux_installer.sh scripts/run_linux.sh 2>/dev/null; bash scripts/build_linux_installer.sh"
wsl -e bash -c $cmd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Done. Output: build/tv-app-books_*.deb" -ForegroundColor Green
