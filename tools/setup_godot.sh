#!/usr/bin/env bash
# Reproducible Godot toolchain setup for this container.
#
# Why each piece:
#  - Godot 4.3 linux binary: fetched from GitHub releases (the one reachable host).
#  - mesa-vulkan-drivers: provides lavapipe (lvp), a SOFTWARE Vulkan device, which is what
#    lets Godot's Forward+ renderer (SDFGI/SSAO/SSIL/volumetric fog/glow) run with no GPU.
#  - Xvfb: Godot needs a display to render; --headless disables rendering entirely, so we run
#    the real renderer against a virtual framebuffer instead.
# Re-run after a container restart:  bash tools/setup_godot.sh
set -euo pipefail

GODOT_VER="4.3-stable"
GODOT_BIN="/opt/godot/godot"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"

if [ ! -x "$GODOT_BIN" ]; then
  echo "==> downloading Godot ${GODOT_VER}"
  mkdir -p /opt/godot /tmp/_gd
  curl -sSL --max-time 180 -o /tmp/_gd/godot.zip "$URL"
  unzip -oq /tmp/_gd/godot.zip -d /tmp/_gd
  mv /tmp/_gd/Godot_v${GODOT_VER}_linux.x86_64 "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -rf /tmp/_gd
fi
echo "==> godot: $("$GODOT_BIN" --headless --version 2>/dev/null | tail -1)"

if [ ! -f /usr/share/vulkan/icd.d/lvp_icd.json ]; then
  echo "==> installing software Vulkan (lavapipe) for Forward+"
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -q mesa-vulkan-drivers >/dev/null 2>&1
fi
echo "==> vulkan icd: $(ls /usr/share/vulkan/icd.d/ 2>/dev/null | tr '\n' ' ')"

command -v xvfb-run >/dev/null || { echo "!! xvfb-run missing"; exit 1; }
echo "==> xvfb: ok"
echo "SETUP OK"
