#!/usr/bin/env bash

set -euo pipefail

: "${VERSION:?Set VERSION to the release version}"
: "${SOURCE_SHA:?Set SOURCE_SHA to the source commit}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"

if git show-ref --verify --quiet "refs/tags/${VERSION}"; then
    TAG_COMMIT=$(git rev-parse "${VERSION}^{commit}")
    if [[ "$TAG_COMMIT" != "$SOURCE_SHA" ]]; then
        printf 'Tag %s does not match source commit %s\n' "$VERSION" "$SOURCE_SHA" >&2
        exit 1
    fi
else
    git tag "$VERSION" "$SOURCE_SHA"
fi
git push origin "refs/tags/${VERSION}"

RELEASE_TAGS=$(gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate --jq '.[].tag_name')
RELEASE_EXISTS=false
while IFS= read -r RELEASE_TAG; do
    if [[ "$RELEASE_TAG" == "$VERSION" ]]; then
        RELEASE_EXISTS=true
    fi
done <<< "$RELEASE_TAGS"

if [[ "$RELEASE_EXISTS" == true ]]; then
    IS_DRAFT=$(gh release view "$VERSION" --json isDraft --jq .isDraft)
    if [[ "$IS_DRAFT" != true ]]; then
        printf 'Release %s already exists; published assets cannot change\n' "$VERSION" >&2
        exit 1
    fi
else
    gh release create "$VERSION" --verify-tag --draft --title "Periphery ${VERSION}" --generate-notes
fi

gh release upload "$VERSION" --clobber \
    "release/periphery-${VERSION}-macos-arm64.zip" \
    "release/periphery-${VERSION}-macos-arm64.dmg" \
    "release/periphery-bazel-${VERSION}.zip" \
    release/install.sh release/checksums.txt
gh release edit "$VERSION" --draft=false --latest
