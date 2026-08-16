#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPORARY_DIRECTORY=$(mktemp -d)

cleanup() {
    rm -rf "${TEMPORARY_DIRECTORY}"
}
trap cleanup EXIT

VERSION=3.8.0-agoodkind.2
FIXTURE_DIRECTORY="${TEMPORARY_DIRECTORY}/release"
INSTALL_DIRECTORY="${TEMPORARY_DIRECTORY}/bin"
mkdir -p "${FIXTURE_DIRECTORY}/periphery-${VERSION}"

cat > "${FIXTURE_DIRECTORY}/periphery-${VERSION}/periphery" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "version" ]]; then
    printf 'Periphery 3.8.0-agoodkind.2\n'
fi
EOF
chmod +x "${FIXTURE_DIRECTORY}/periphery-${VERSION}/periphery"

(
    cd "${FIXTURE_DIRECTORY}"
    ditto -c -k --sequesterRsrc --keepParent "periphery-${VERSION}" "periphery-${VERSION}-macos-universal.zip"
    shasum -a 256 "periphery-${VERSION}-macos-universal.zip" > "checksums.txt"
)

PERIPHERY_RELEASE_BASE_URL="file://${FIXTURE_DIRECTORY}" \
    INSTALL_DIR="${INSTALL_DIRECTORY}" \
    "${REPOSITORY_ROOT}/scripts/install.sh"

test -x "${INSTALL_DIRECTORY}/periphery"
test "$("${INSTALL_DIRECTORY}/periphery" version)" = "Periphery ${VERSION}"

printf 'corrupt archive' > "${FIXTURE_DIRECTORY}/periphery-${VERSION}-macos-universal.zip"
if PERIPHERY_RELEASE_BASE_URL="file://${FIXTURE_DIRECTORY}" \
    INSTALL_DIR="${TEMPORARY_DIRECTORY}/failed-install" \
    "${REPOSITORY_ROOT}/scripts/install.sh"; then
    printf 'Installer accepted a corrupt archive\n' >&2
    exit 1
fi
test ! -e "${TEMPORARY_DIRECTORY}/failed-install/periphery"
