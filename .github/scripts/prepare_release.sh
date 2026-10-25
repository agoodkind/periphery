#!/usr/bin/env bash

set -euo pipefail

: "${SOURCE_SHA?Set SOURCE_SHA; use an empty value to select HEAD}"
: "${REQUESTED_TAG?Set REQUESTED_TAG; use an empty value for an automatic release}"
: "${GITHUB_OUTPUT:?Set GITHUB_OUTPUT to the workflow output file}"
: "${GITHUB_ENV:?Set GITHUB_ENV to the workflow environment file}"

HEAD_SHA=$(git rev-parse HEAD)
if [[ -n "$SOURCE_SHA" && "$SOURCE_SHA" != "$HEAD_SHA" ]]; then
    printf 'SOURCE_SHA must equal the checked-out commit %s\n' "$HEAD_SHA" >&2
    exit 1
fi
SOURCE_SHA=$HEAD_SHA

VERSION_PATTERN='^3\.8\.0-agoodkind\.([0-9]+)$'
if [[ -n "$REQUESTED_TAG" ]]; then
    if [[ ! "$REQUESTED_TAG" =~ $VERSION_PATTERN ]]; then
        printf 'REQUESTED_TAG must match 3.8.0-agoodkind.N with a numeric suffix\n' >&2
        exit 1
    fi
    if ! git show-ref --verify --quiet "refs/tags/$REQUESTED_TAG"; then
        printf 'Requested release tag %s does not exist; create it before dispatch\n' "$REQUESTED_TAG" >&2
        exit 1
    fi
    TAG_SHA=$(git rev-parse "${REQUESTED_TAG}^{commit}")
    if [[ "$TAG_SHA" != "$SOURCE_SHA" ]]; then
        printf 'Requested release tag %s must identify the checked-out commit %s\n' "$REQUESTED_TAG" "$SOURCE_SHA" >&2
        exit 1
    fi
    VERSION=$REQUESTED_TAG
else
    TAGS=$(git tag --list '3.8.0-agoodkind.*')
    MAXIMUM_SUFFIX=0
    MATCHED_SUFFIX=-1
    VERSION=''
    while IFS= read -r TAG; do
        if [[ ! "$TAG" =~ $VERSION_PATTERN ]]; then
            continue
        fi
        SUFFIX=$((10#${BASH_REMATCH[1]}))
        if (( SUFFIX > MAXIMUM_SUFFIX )); then
            MAXIMUM_SUFFIX=$SUFFIX
        fi
        TAG_SHA=$(git rev-parse "${TAG}^{commit}")
        if [[ "$TAG_SHA" == "$SOURCE_SHA" ]] && (( SUFFIX > MATCHED_SUFFIX )); then
            MATCHED_SUFFIX=$SUFFIX
            VERSION=$TAG
        fi
    done <<< "$TAGS"
    if [[ -z "$VERSION" ]]; then
        VERSION="3.8.0-agoodkind.$((MAXIMUM_SUFFIX + 1))"
    fi
fi

INSTALLER_TEMPORARY=$(mktemp -t periphery-release)
trap 'rm -f "$INSTALLER_TEMPORARY"' EXIT
INSTALLER_VERSION_UPDATED=false
while IFS= read -r INSTALLER_LINE; do
    if [[ "$INSTALLER_LINE" == VERSION=* ]]; then
        printf 'VERSION=%s\n' "$VERSION"
        INSTALLER_VERSION_UPDATED=true
    else
        printf '%s\n' "$INSTALLER_LINE"
    fi
done < scripts/install.sh > "$INSTALLER_TEMPORARY"
if [[ "$INSTALLER_VERSION_UPDATED" != true ]]; then
    printf 'scripts/install.sh must contain the VERSION assignment\n' >&2
    exit 1
fi

printf 'let PeripheryVersion = "%s"\n' "$VERSION" > Sources/Frontend/Version.swift
cat "$INSTALLER_TEMPORARY" > scripts/install.sh
printf 'version=%s\nsource_sha=%s\n' "$VERSION" "$SOURCE_SHA" >> "$GITHUB_OUTPUT"
printf 'VERSION=%s\n' "$VERSION" >> "$GITHUB_ENV"
