#!/bin/bash
# Parse + run the project headless for a few seconds; print script errors.
PROJ="${1:-game}"; shift
timeout 120 godot --headless --path "$PROJ" --import >/dev/null 2>&1
timeout 120 godot --headless --path "$PROJ" --quit-after ${FRAMES:-240} "$@" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR|WARNING|at: |GDScript backtrace|\[[0-9]+\]" | grep -vE "audio|ALSA|sfx.gd.*not found" | head -${LINES_MAX:-40}
