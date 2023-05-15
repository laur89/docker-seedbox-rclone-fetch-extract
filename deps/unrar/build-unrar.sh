#!/usr/bin/env bash
#
# builds unrar pkg off Dockerfile, and copies results to $TARGET_DIR

#####################################
readonly SELF="${0##*/}"
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # location of this script
TAG="${SELF}-$RANDOM"
TARGET_DIR="${DIR}/../builds"
#####################################

[[ -d "$TARGET_DIR" ]] || exit 1

# build image that buids unrar pkg:
docker build -t "$TAG" -- . || exit 1
# start the container so we can copy packages to the mount (docker build doesn't allow mounts, hence why we do this):
docker run --rm -v "${TARGET_DIR}:/out" -- "$TAG" find /build/unrar-target -maxdepth 1 -mindepth 1 -type f -exec cp -t /out {} + || exit 1

docker image rm "$TAG" || exit 1

exit 0

