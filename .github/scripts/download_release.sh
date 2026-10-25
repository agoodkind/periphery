#!/usr/bin/env bash

set -euo pipefail

: "${VERSION:?Set VERSION to the release version}"

mkdir -p release
gh release download "$VERSION" --dir release \
    --pattern "periphery-${VERSION}-macos-arm64.zip" --pattern checksums.txt
cd release
EXPECTED_SHA=$(awk -v archive="periphery-${VERSION}-macos-arm64.zip" '$2 == archive {print $1}' checksums.txt)
if [[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'Release %s must include one archive checksum\n' "$VERSION" >&2
    exit 1
fi
printf '%s  %s\n' "$EXPECTED_SHA" "periphery-${VERSION}-macos-arm64.zip" | shasum -a 256 --check
