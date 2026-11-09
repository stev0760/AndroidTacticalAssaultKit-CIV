#!/bin/bash
# Run a command inside the ATAK build container.
#   scripts/container/run.sh                -> interactive shell
#   scripts/container/run.sh <cmd...>       -> run command
# Persistent state (Android SDK/NDK, ~/.gradle, ~/.conan, ~/.m2) lives in
# ${ATAK_BUILD_CACHE:-~/.cache/atak-build}.
set -e
REPO=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
CACHE=${ATAK_BUILD_CACHE:-$HOME/.cache/atak-build}
mkdir -p "$CACHE/android" "$CACHE/home"
TTY=; [ -t 0 ] && TTY=-it
exec podman run --rm $TTY \
  -v "$REPO:/src:z" \
  -v "$CACHE/android:/opt/android:z" \
  -v "$CACHE/home:/root:z" \
  -w /src \
  localhost/atak-build "${@:-bash}"
