#!/bin/bash
# Run everything CI runs: unit tests and manifest validation.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Unit tests"
node --test tests/*.test.cjs

echo "==> Manifest"
if command -v omarchy-plugin-validate >/dev/null; then
  omarchy-plugin-validate "$ROOT"
else
  "$ROOT/scripts/validate-manifest.sh" "$ROOT"
fi
echo "manifest OK"
