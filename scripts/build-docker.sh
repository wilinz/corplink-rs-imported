#!/usr/bin/env bash
# Build the corplink-rs container image locally (works with docker or podman).
#
#   ./scripts/build-docker.sh [tag] [platform]
#
# examples:
#   ./scripts/build-docker.sh                          # corplink-rs:local, host arch
#   ./scripts/build-docker.sh corplink-rs:dev
#   ./scripts/build-docker.sh corplink-rs:dev linux/amd64
#
# override the engine with: ENGINE=podman ./scripts/build-docker.sh
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:-corplink-rs:local}"
PLATFORM="${2:-}"

# pick a container engine
ENGINE="${ENGINE:-}"
if [ -z "$ENGINE" ]; then
  if command -v docker >/dev/null 2>&1; then ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then ENGINE=podman
  else echo "neither docker nor podman found" >&2; exit 1
  fi
fi

# the SOCKS5/netstack code lives in the wireguard-go submodule; make sure it's
# checked out so it ends up in the build context.
git submodule update --init --recursive

BUILD_ARGS=()
if [ -n "$PLATFORM" ]; then
  BUILD_ARGS+=(--platform "$PLATFORM")
  # match the Go toolchain download to the target arch (amd64/arm64)
  BUILD_ARGS+=(--build-arg "TARGETARCH=${PLATFORM##*/}")
fi

echo "building with $ENGINE: $TAG ${PLATFORM:+($PLATFORM)}"
"$ENGINE" build "${BUILD_ARGS[@]}" -t "$TAG" .

echo
echo "built: $TAG"
echo "run:   $ENGINE run --rm -p 1080:1080 -v \"\$PWD/data:/data\" $TAG"
echo "       (put your config.json with \"socks5_listen\": \"0.0.0.0:1080\" in ./data)"
