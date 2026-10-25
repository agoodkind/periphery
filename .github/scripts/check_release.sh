#!/usr/bin/env bash

set -euo pipefail

: "${VERSION:?Set VERSION to the release version}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
: "${GITHUB_OUTPUT:?Set GITHUB_OUTPUT}"

RELEASE_TAGS=$(gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate --jq '.[] | select(.draft == false) | .tag_name')
while IFS= read -r RELEASE_TAG; do
    if [[ "$RELEASE_TAG" == "$VERSION" ]]; then
        ASSET_NAMES=$(gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name')
        for EXPECTED_ASSET in "periphery-${VERSION}-macos-arm64.zip" "periphery-${VERSION}-macos-arm64.dmg" "periphery-bazel-${VERSION}.zip" install.sh checksums.txt; do
            if ! grep -Fxq "$EXPECTED_ASSET" <<< "$ASSET_NAMES"; then
                printf 'Published release %s lacks %s. Dispatch with an empty tag to create a complete release.\n' "$VERSION" "$EXPECTED_ASSET" >&2
                exit 1
            fi
        done
        printf 'exists=true\n' >> "$GITHUB_OUTPUT"
        printf 'Reusing published release %s\n' "$VERSION"
        exit 0
    fi
done <<< "$RELEASE_TAGS"
printf 'exists=false\n' >> "$GITHUB_OUTPUT"
