# Build and run tv_app_books on Windows
# Run from project root in a terminal where Flutter is in PATH:
#   .\build_and_run_windows.ps1

Set-Location $PSScriptRoot

Write-Host "Building Windows app..." -ForegroundColor Cyan
flutter build windows
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

Write-Host "Launching app..." -ForegroundColor Green
Start-Process ".\build\windows\x64\runner\Release\tv_app_books.exe"
