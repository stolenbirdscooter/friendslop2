#!/bin/bash
# Usage: tools/shot.sh <project_dir> <scene_res_path> <out.png> [user args...]
# Renders one frame with software Vulkan under Xvfb.
PROJ="$1"; SCENE="$2"; OUT="$3"; shift 3
timeout 120 godot --headless --path "$PROJ" --import >/dev/null 2>&1
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout 300 xvfb-run -a -s "-screen 0 1600x900x24" \
  godot --path "$PROJ" --resolution 1600x900 "$SCENE" -- --shot="$OUT" "$@" 2>&1 \
  | grep -vE "ALSA|audio_driver_alsa|All audio drivers|init_output_device|audio_server.cpp|^\s*$|_snd_|snd_" | tail -25
