# Building Windows release with Docker

Requires **Docker with Windows containers** (not WSL2 Linux containers). Switch to Windows containers in Docker Desktop if needed.

## Build the image

From the project root (where `pubspec.yaml` is):

```powershell
docker build -f Dockerfile.windows -t tv-app-books-windows .
```

This will:

- Use a Windows Server Core base image
- Install Visual Studio Build Tools (C++ workload) and Git
- Download the Flutter SDK (stable Windows zip)
- Copy your app and run `flutter pub get` and `flutter build windows --release`

The first build is slow (large image and VS Build Tools). Later builds use cache.

## Get the release output

The Windows release is produced inside the container at:

`C:\app\build\windows\x64\runner\Release`

To copy it out, run the container with a volume and copy the folder:

```powershell
# Create output folder
New-Item -ItemType Directory -Force -Path .\release-out

# Run container and copy release folder to host
docker run --rm -v "${PWD}:C:\app" -v "${PWD}\release-out:C:\out" tv-app-books-windows powershell -Command "Copy-Item -Path 'C:\app\build\windows\x64\runner\Release\*' -Destination 'C:\out' -Recurse -Force; Get-ChildItem C:\out"
```

Then open `.\release-out` on your machine. It will contain `tv_app_books.exe` and the required DLLs.

## Override Flutter version

To use a different Flutter stable zip:

```powershell
docker build -f Dockerfile.windows --build-arg FLUTTER_ZIP_URL=https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.22.0-stable.zip -t tv-app-books-windows .
```

## Resource tips

Windows containers often need more CPU/memory. If the build fails, try:

```powershell
docker run --rm --cpu-count 4 --memory 6gb -v "${PWD}:C:\app" -v "${PWD}\release-out:C:\out" tv-app-books-windows ...
```
