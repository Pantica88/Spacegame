#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
    godot_bin="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$godot_bin" && -x /tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64 ]]; then
    godot_bin=/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64
fi
if [[ -z "$godot_bin" ]] || ! command -v "$godot_bin" >/dev/null 2>&1; then
    printf '%s\n' 'Godot was not found. Install Godot 4.5.1 Standard, or set GODOT_BIN to its executable.' >&2
    exit 1
fi
exec "$godot_bin" --path "$project_dir" "$@"

