#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
for test in runtime-policy runtime-attestation review-documents post-comment; do
    "$DIR/$test.sh"
done
