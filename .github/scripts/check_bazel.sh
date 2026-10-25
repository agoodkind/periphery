#!/usr/bin/env bash

set -euo pipefail

: "${VERSION:?Set VERSION to the release version}"
: "${GITHUB_OUTPUT:?Set GITHUB_OUTPUT}"

VERSIONS=$(gh api repos/bazelbuild/bazel-central-registry/contents/modules/periphery/metadata.json \
    -H 'Accept: application/vnd.github.raw+json' --jq '.versions[]')
while IFS= read -r REGISTERED_VERSION; do
    if [[ "$REGISTERED_VERSION" == "$VERSION" ]]; then
        printf 'exists=true\n' >> "$GITHUB_OUTPUT"
        printf 'Bazel Central Registry already includes %s\n' "$VERSION"
        exit 0
    fi
done <<< "$VERSIONS"

: "${BCR_PUBLISH_TOKEN:?Configure the BCR_PUBLISH_TOKEN Actions secret with a dedicated classic token with repo and workflow scopes}"
printf 'exists=false\n' >> "$GITHUB_OUTPUT"
