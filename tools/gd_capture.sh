#!/usr/bin/env bash
# Run the Godot game under a virtual framebuffer and capture rendered frames.
#
# The engine-side agent (godot/scripts/capture.gd) does the actual grabbing and waits on
# RENDERED FRAMES, so results are deterministic even though lavapipe (software Vulkan) is slow.
#
# Usage: tools/gd_capture.sh --out captures/gd/foo [--shots 6] [--gap 30] [--strip 12] [--warm 40]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-/opt/godot/godot}"
[ -x "$GODOT" ] || { echo "godot missing — run: bash tools/setup_godot.sh"; exit 1; }

OUT=""; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; ARGS+=(--out); shift 2;;
    *) ARGS+=("$1"); shift;;
  esac
done
[ -n "$OUT" ] || { echo "need --out DIR"; exit 1; }
case "$OUT" in /*) ABS="$OUT";; *) ABS="$ROOT/$OUT";; esac
mkdir -p "$ABS"

# rebuild the arg list with the absolute out dir in the right position
FINAL=(); for a in "${ARGS[@]}"; do if [ "$a" = "--out" ]; then FINAL+=(--out "$ABS"); else FINAL+=("$a"); fi; done

timeout "${GD_TIMEOUT:-600}" xvfb-run -a -s "-screen 0 1600x1000x24" \
  "$GODOT" --path "$ROOT/godot" --resolution 1600x1000 -- "${FINAL[@]}" 2>&1 \
  | grep -viE "alsa|pulse|audio driver|ERROR: Condition \"status < 0\"" \
  | tail -25

echo "--- frames in $ABS ---"
ls -1 "$ABS" 2>/dev/null | head -30
