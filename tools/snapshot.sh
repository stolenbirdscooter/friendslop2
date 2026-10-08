#!/bin/bash
# Freeze the current game/ into versions/<tag>/ as a standalone Godot project.
# Usage: tools/snapshot.sh v0.1-first-steps "First Steps"
set -e
TAG="$1"; LABEL="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/versions/$TAG"
[ -e "$DEST" ] && { echo "exists: $DEST"; exit 1; }
mkdir -p "$DEST"
(cd "$ROOT/game" && tar cf - --exclude=./.godot --exclude=./build .) | (cd "$DEST" && tar xf -)
VER="${TAG%%-*}"
sed -i "s|^config/name=.*|config/name=\"Mossback $VER — $LABEL\"|" "$DEST/project.godot"
# the snapshot must import and boot on its own
timeout 180 godot --headless --path "$DEST" --import >/dev/null 2>&1 || true
OUT=$(timeout 120 godot --headless --path "$DEST" --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|Parse Error" || true)
rm -rf "$DEST/.godot"
if [ -n "$OUT" ]; then echo "$OUT"; echo "SNAPSHOT HAS ERRORS"; exit 1; fi
echo "snapshot ok: $DEST"
