# Building Linux release with Docker

Requires **Docker** with **BuildKit** enabled (default in recent Docker Desktop / `docker buildx`). From the project root (`pubspec.yaml` here).

On **ARM** hosts (e.g. Apple Silicon), force amd64 so Flutter Linux x64 matches the bundle:

`docker build --platform linux/amd64 ...`

Artifacts inside the image (under `/artifacts`):

| File / folder | Description |
|---------------|-------------|
| `app-release_Dev.deb` | Dev build (`BUILD_ENV=Dev`) |
| `app-release_Prod.deb` | Prod build (`BUILD_ENV=Prod`) |
| `linux-bundle_Dev/` | Release bundle (Dev) |
| `linux-bundle_Prod/` | Release bundle (Prod) |

Dart compile-time defines:

- `PACKAGE_SUFFIX` is set to `_Dev` or `_Prod` (same as before).
- `BUILD_ENV` is set to `Dev` or `Prod`.
- `BACKEND_URL` is a normal `--build-arg`.
- `BOOK_KEY` is passed with **`--secret`** so it is not stored in image history (see below).

## Dev build

```bash
docker build -f Dockerfile.linux -t tv-app-books-linux:dev \
  --build-arg BUILD_ENV=Dev \
  --build-arg BACKEND_URL="https://your-dev-api.example/" \
  .
```

With a book key from your environment (not shown in `docker history`):

```bash
docker build -f Dockerfile.linux -t tv-app-books-linux:dev \
  --build-arg BUILD_ENV=Dev \
  --build-arg BACKEND_URL="https://your-dev-api.example/" \
  --secret id=book_key,env=MY_BOOK_KEY \
  .
# export MY_BOOK_KEY='...' first, or use --secret id=book_key,src=./key.txt
```

## Prod build

```bash
docker build -f Dockerfile.linux -t tv-app-books-linux:prod \
  --build-arg BUILD_ENV=Prod \
  --build-arg BACKEND_URL="https://your-prod-api.example/" \
  .
```

With secret (same pattern as dev):

```bash
docker build ... --secret id=book_key,env=MY_BOOK_KEY .
```

Replace URLs and secrets as needed. Omit `--secret` if `BOOK_KEY` should be empty.

**Important:** Dev and prod are **two separate images**. You must run **both** `docker build` commands if you want both `.deb` files. If you only built `:dev`, `docker create tv-app-books-linux:prod` will fail with *pull access denied* / *image not found*, and `cid` will be empty (so `docker cp` / `docker rm` error).

## Copy artifacts to the host

**After each build**, copy that tag only (or use the helper script below).

```bash
# After dev build only
bash scripts/docker_linux_extract.sh tv-app-books-linux:dev dev

# After prod build only (run the Prod docker build first!)
bash scripts/docker_linux_extract.sh tv-app-books-linux:prod prod
```

Manual equivalent:

```bash
# Dev (after building tv-app-books-linux:dev)
mkdir -p docker-artifacts/dev
cid=$(docker create tv-app-books-linux:dev)
docker cp "$cid:/artifacts/." docker-artifacts/dev/
docker rm "$cid"

# Prod (only after building tv-app-books-linux:prod)
mkdir -p docker-artifacts/prod
cid=$(docker create tv-app-books-linux:prod)
docker cp "$cid:/artifacts/." docker-artifacts/prod/
docker rm "$cid"
```

## Install the `.deb` (on Ubuntu/Debian)

```bash
sudo dpkg -i docker-artifacts/prod/app-release_Prod.deb
sudo apt-get install -f
```

## Notes

- The **internal** Debian package name in `DEBIAN/control` remains `tv-app-books` with version `1.0.0`; only the **artifact filenames** on disk are `app-release_Dev.deb` / `app-release_Prod.deb`.
- If your GitLab `app-template` release job expects older artifact names, update that template to pick up `app-release_${BUILD_ENV}.deb`.
- **Lint / Scout:** `BOOK_KEY` is not an `ARG` (it uses `--secret`), and `FROM` does not pin `--platform` (use `docker build --platform linux/amd64` when you need amd64 on ARM).

### GitLab CI variables

Linux Docker jobs expect **`DEV_BOOK_CI_KEY`** / **`PROD_BOOK_CI_KEY`** to exist in the project (value may be empty). If Docker errors on `--secret ...env=...`, define the variable in GitLab (even as an empty protected variable).
