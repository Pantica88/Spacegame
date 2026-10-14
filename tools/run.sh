#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"
# Prefer the double-precision build (see docs/MULTI_PLANET_ROADMAP.md, step 1):
# 4.7.2 (src-4.7), else the previous 4.5.1 build (src).
for double_bin in "$HOME/godot-double/src-4.7/bin/godot.linuxbsd.editor.double.x86_64" \
        "$HOME/godot-double/src/bin/godot.linuxbsd.editor.double.x86_64"; do
    if [[ -z "$godot_bin" && -x "$double_bin" ]]; then
        godot_bin="$double_bin"
    fi
done
if [[ -z "$godot_bin" ]]; then
    godot_bin="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$godot_bin" && -x /tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64 ]]; then
    godot_bin=/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64
fi
if [[ -z "$godot_bin" ]] || ! command -v "$godot_bin" >/dev/null 2>&1; then
    printf '%s\n' 'Godot was not found. Build the double-precision editor (docs/MULTI_PLANET_ROADMAP.md, step 1), or set GODOT_BIN to its executable.' >&2
    exit 1
fi
exec "$godot_bin" --path "$project_dir" "$@"

