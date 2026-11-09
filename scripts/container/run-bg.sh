#!/bin/bash
# Run a long build step detached inside the build container, logging to
# .buildlogs/<name>.log (with a final "EXIT <code>" line).
#   scripts/container/run-bg.sh <name> '<shell command>'
set -e
REPO=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
CACHE=${ATAK_BUILD_CACHE:-$HOME/.cache/atak-build}
NAME=$1; shift
mkdir -p "$REPO/.buildlogs" "$CACHE/android" "$CACHE/home"
podman run -d --name "atak-$NAME" --replace \
  -v "$REPO:/src:z" -v "$CACHE/android:/opt/android:z" -v "$CACHE/home:/root:z" \
  -w /src localhost/atak-build \
  bash -c "( $* ) > /src/.buildlogs/$NAME.log 2>&1; echo EXIT \$? >> /src/.buildlogs/$NAME.log"
