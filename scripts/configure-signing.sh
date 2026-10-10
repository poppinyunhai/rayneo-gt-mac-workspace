#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" != "1" || ! "$1" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf 'Usage: bash scripts/configure-signing.sh CERTIFICATE_SHA1\nAvailable identities:\n' >&2
    security find-identity -v -p codesigning
    exit 1
fi
task_identity="$1"
if ! security find-identity -v -p codesigning | rg -qi -- "$task_identity"; then
    printf 'Certificate is not a valid installed code-signing identity.\n' >&2;exit 1
fi
printf '%s\n' "$task_identity" > .signing-identity
printf 'Pinned local signing identity: %s\n' "$task_identity"
