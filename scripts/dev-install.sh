#!/bin/bash
# Copy the working tree into the local Omarchy plugin directory and restart the
# shell so the change is picked up (plugin hot-reload can keep stale QML cached).
#
#   scripts/dev-install.sh           install/update and restart the shell
#   scripts/dev-install.sh --enable  also enable the plugin (bar: right section)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="$(jq -r '.id' "$ROOT/manifest.json")"
TARGET="$HOME/.config/omarchy/plugins/$ID"

if [[ -d $TARGET/.git ]]; then
  echo "dev-install: $TARGET is a git checkout (installed with 'omarchy plugin add')." >&2
  echo "dev-install: remove it with 'omarchy plugin remove $ID' first." >&2
  exit 1
fi

"$ROOT/scripts/check.sh"

mkdir -p "$TARGET"
rsync -a --delete \
  --exclude '.git/' --exclude '.github/' --exclude 'tests/' --exclude 'scripts/' \
  "$ROOT/" "$TARGET/"
echo "Installed $ID into $TARGET"

if [[ ${1:-} == --enable ]]; then
  # The shell has to discover a newly copied plugin before it can be enabled.
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy plugin enable "$ID" --section right
fi

omarchy restart shell
