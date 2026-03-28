#!/usr/bin/env bash
# Copy /artifacts from a built Linux Docker image to docker-artifacts/<subdir>/.
# Usage: bash scripts/docker_linux_extract.sh <image:tag> <subdir>
# Example: bash scripts/docker_linux_extract.sh tv-app-books-linux:dev dev

set -euo pipefail
IMAGE="${1:?Usage: $0 <image:tag> <subdir>   e.g. tv-app-books-linux:dev dev}"
SUBDIR="${2:?second arg: subdir under docker-artifacts/}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$ROOT/docker-artifacts/$SUBDIR"

if ! docker image inspect "$IMAGE" &>/dev/null; then
  echo "Error: Docker image not found: $IMAGE"
  echo "Build it first, for example:"
  echo "  docker build -f Dockerfile.linux -t $IMAGE \\"
  echo "    --build-arg BUILD_ENV=Prod --build-arg BACKEND_URL=... \\"
  echo "    --secret id=book_key,env=YOUR_KEY_VAR ."
  exit 1
fi

mkdir -p "$OUT"
cid="$(docker create "$IMAGE")"
docker cp "$cid:/artifacts/." "$OUT/"
docker rm "$cid"
echo "Artifacts -> $OUT"
ls -la "$OUT"
