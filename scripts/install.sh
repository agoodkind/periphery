#!/usr/bin/env bash

set -euo pipefail

VERSION=3.8.0-agoodkind.2
ARCHIVE_NAME="periphery-${VERSION}-macos-universal.zip"
CHECKSUMS_NAME=checksums.txt
RELEASE_BASE_URL=${PERIPHERY_RELEASE_BASE_URL:-"https://github.com/agoodkind/periphery/releases/download/${VERSION}"}
INSTALL_DIRECTORY=${INSTALL_DIR:-"${HOME}/.local/bin"}
TEMPORARY_DIRECTORY=$(mktemp -d)

cleanup() {
    rm -rf "${TEMPORARY_DIRECTORY}"
}
trap cleanup EXIT

mkdir -p "${INSTALL_DIRECTORY}"

ARCHIVE_PATH="${TEMPORARY_DIRECTORY}/${ARCHIVE_NAME}"
CHECKSUMS_PATH="${TEMPORARY_DIRECTORY}/${CHECKSUMS_NAME}"
EXTRACT_DIRECTORY="${TEMPORARY_DIRECTORY}/extract"
TEMPORARY_BINARY="${INSTALL_DIRECTORY}/.periphery.${RANDOM}.${RANDOM}"

curl --fail --location --retry 3 --silent --show-error --output "${ARCHIVE_PATH}" "${RELEASE_BASE_URL}/${ARCHIVE_NAME}"
curl --fail --location --retry 3 --silent --show-error --output "${CHECKSUMS_PATH}" "${RELEASE_BASE_URL}/${CHECKSUMS_NAME}"

EXPECTED_SHA256=$(awk -v archive_name="${ARCHIVE_NAME}" '$2 == archive_name { print $1; exit }' "${CHECKSUMS_PATH}")
if [[ -z "${EXPECTED_SHA256}" ]]; then
    printf 'Missing checksum for %s\n' "${ARCHIVE_NAME}" >&2
    exit 1
fi

ACTUAL_SHA256=$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{ print $1 }')
if [[ "${EXPECTED_SHA256}" != "${ACTUAL_SHA256}" ]]; then
    printf 'Checksum verification failed for %s\n' "${ARCHIVE_NAME}" >&2
    exit 1
fi

mkdir -p "${EXTRACT_DIRECTORY}"
unzip -q "${ARCHIVE_PATH}" -d "${EXTRACT_DIRECTORY}"
install -m 755 "${EXTRACT_DIRECTORY}/periphery-${VERSION}/periphery" "${TEMPORARY_BINARY}"
mv -f "${TEMPORARY_BINARY}" "${INSTALL_DIRECTORY}/periphery"
"${INSTALL_DIRECTORY}/periphery" version
