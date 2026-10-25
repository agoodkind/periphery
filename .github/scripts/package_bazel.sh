#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: package_bazel.sh VERSION OUTPUT_DIRECTORY SOURCE_DIRECTORY\n' >&2
    exit 1
fi

VERSION=$1
OUTPUT_DIRECTORY=$2
if [[ ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*$ ]]; then
    printf 'VERSION must start with a letter or digit and contain only letters, digits, periods, plus signs, or hyphens\n' >&2
    exit 1
fi

REPOSITORY_ROOT=$(realpath "$3")
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY=$(realpath "$OUTPUT_DIRECTORY")
STAGING_DIRECTORY=$(mktemp -d)

cleanup() {
    rm -rf "$STAGING_DIRECTORY"
}
trap cleanup EXIT

cp "$REPOSITORY_ROOT/LICENSE.md" "$REPOSITORY_ROOT/BUILD.bazel" "$STAGING_DIRECTORY/"
cp -R "$REPOSITORY_ROOT/bazel" "$REPOSITORY_ROOT/Sources" "$STAGING_DIRECTORY/"

VERSION_UPDATED=false
while IFS= read -r MODULE_LINE; do
    if [[ "$MODULE_LINE" == '    version = '* && "$VERSION_UPDATED" == false ]]; then
        printf '    version = "%s",\n' "$VERSION"
        VERSION_UPDATED=true
    else
        printf '%s\n' "$MODULE_LINE"
    fi
done < "$REPOSITORY_ROOT/MODULE.bazel" > "$STAGING_DIRECTORY/MODULE.bazel"

if [[ "$VERSION_UPDATED" != true ]]; then
    printf 'MODULE.bazel must contain the module version declaration\n' >&2
    exit 1
fi

cd "$STAGING_DIRECTORY"
zip -qr periphery-bazel.zip LICENSE.md MODULE.bazel BUILD.bazel bazel Sources -x 'bazel/dev/*'
mv periphery-bazel.zip "$OUTPUT_DIRECTORY/periphery-bazel-${VERSION}.zip"
printf '%s\n' "$OUTPUT_DIRECTORY/periphery-bazel-${VERSION}.zip"
