#!/usr/bin/env bash
set -euo pipefail

if ! command -v xattr >/dev/null 2>&1; then
  exit 0
fi

if [[ "$#" -eq 0 ]]; then
  set -- \
    "apps/LLMAB-macOS" \
    "assets"
fi

for path in "$@"; do
  [[ -e "$path" ]] || continue
  xattr -cr "$path" 2>/dev/null || true
done
