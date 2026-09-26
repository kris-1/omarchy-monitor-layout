#!/bin/bash
# Standalone subset of `omarchy plugin validate`, for machines (CI) without
# Omarchy installed. On an Omarchy system, scripts/check.sh uses the real one.

set -euo pipefail

DIR="${1:-.}"
MANIFEST="$DIR/manifest.json"

fail() { echo "validate-manifest: $*" >&2; exit 1; }

[[ -f $MANIFEST ]] || fail "missing $MANIFEST"
jq -e . "$MANIFEST" >/dev/null || fail "manifest.json is not valid JSON"
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null || fail "schemaVersion must be 1"
for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null || fail "missing field '$field'"
done

id=$(jq -r '.id' "$MANIFEST")
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *".."* ]] || fail "invalid id '$id'"
[[ $id != omarchy.* ]] || fail "id '$id' uses the reserved omarchy.* namespace"

while IFS= read -r ep; do
  [[ $ep != /* && $ep != *".."* ]] || fail "unsafe entry point '$ep'"
  [[ -f $DIR/$ep ]] || fail "entry point not found: '$ep'"
done < <(jq -r '.entryPoints[]' "$MANIFEST")

for pair in bar:bar bar-widget:barWidget menu:menu overlay:overlay panel:panel service:service; do
  kind=${pair%%:*}; ep=${pair##*:}
  jq -e --arg k "$kind" '.kinds | index($k) != null' "$MANIFEST" >/dev/null || continue
  jq -e --arg e "$ep" '.entryPoints | has($e)' "$MANIFEST" >/dev/null || fail "kind '$kind' needs entryPoints.$ep"
done

link=$(find "$DIR" -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlinks are not allowed: $link"
