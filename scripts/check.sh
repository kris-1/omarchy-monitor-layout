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

# qmllint cannot resolve the shell's qs.* modules outside omarchy-shell, so
# unqualified/import warnings about Style, Color and qs.Ui types are expected
# (Omarchy's own panels show the same). Only syntax errors fail the check.
if [[ -x /usr/lib/qt6/bin/qmllint && -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell ]]; then
  echo "==> qmllint"
  lint_output=$(/usr/lib/qt6/bin/qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" ./*.qml 2>&1 || true)
  if grep -q "\[syntax\]\|^Error" <<<"$lint_output"; then
    grep "\[syntax\]\|^Error" <<<"$lint_output"
    exit 1
  fi
  echo "qmllint: no syntax errors"
fi
