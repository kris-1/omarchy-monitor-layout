#!/bin/bash
# Copy the working tree into the local Omarchy plugin directory and restart the
# shell so the change is picked up (plugin hot-reload can keep stale QML cached).
#
#   scripts/dev-sync.sh                 install/update and restart the shell
#   scripts/dev-sync.sh --enable        also enable it in place of the built-in Display
#   scripts/dev-sync.sh --service-only  run only the layout service, without the
#                                          widget, next to your own Display widget
#
# --service-only drops omarchy.clonedFrom from the installed copy, so your own
# Display widget stays the only clone of omarchy.monitor: with two clones the
# shell picks one of them for the Display shortcut (SUPER+CTRL+D).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="$(jq -r '.id' "$ROOT/manifest.json")"
TARGET="$HOME/.config/omarchy/plugins/$ID"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
MODE="${1:-}"

if [[ -d $TARGET/.git ]]; then
  echo "dev-sync: $TARGET is a git checkout (installed with 'omarchy plugin add')." >&2
  echo "dev-sync: remove it with 'omarchy plugin remove $ID' first." >&2
  exit 1
fi

"$ROOT/scripts/check.sh"

mkdir -p "$TARGET"
rsync -a --delete \
  --exclude '.git/' --exclude '.github/' --exclude 'tests/' --exclude 'scripts/' \
  "$ROOT/" "$TARGET/"
echo "Installed $ID into $TARGET"

case "$MODE" in
  --enable)
    # The shell has to discover a newly copied plugin before it can be enabled.
    omarchy-shell shell rescanPlugins >/dev/null
    omarchy plugin enable "$ID"
    ;;
  --service-only)
    tmp=$(mktemp)
    jq 'del(.omarchy)' "$TARGET/manifest.json" > "$tmp" && mv "$tmp" "$TARGET/manifest.json"
    tmp=$(mktemp)
    jq --arg id "$ID" '
      .plugins = (((.plugins // []) | map(select(.id != $id))) + [{ id: $id }])
      | if .bar.layout then .bar.layout |= map_values(map(select(.id != $id))) else . end
    ' "$SHELL_CONFIG" > "$tmp" && mv "$tmp" "$SHELL_CONFIG"
    echo "Enabled $ID as a service only (no bar widget)"
    ;;
esac

omarchy restart shell
