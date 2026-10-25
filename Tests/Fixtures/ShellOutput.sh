#!/usr/bin/env bash
set -euo pipefail

PAYLOAD=x
for ((i = 0; i < 18; i++)); do
    PAYLOAD="${PAYLOAD}${PAYLOAD}"
done

printf 'stderr:%s:end' "$PAYLOAD" >&2
printf 'stdout:%s:end' "$PAYLOAD"
exit "${1:?Provide the exit status}"
