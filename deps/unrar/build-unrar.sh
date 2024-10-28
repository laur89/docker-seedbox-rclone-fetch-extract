#!/usr/bin/env bash
#
# builds unrar pkg off Dockerfile, and copies results to $TARGET_DIR

#####################################
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # location of this script
TARGET_DIR="${DIR}/../builds"
#####################################

[[ -d "$TARGET_DIR" ]] || exit 1
docker build  --output "$TARGET_DIR" .

exit 0

