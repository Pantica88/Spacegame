#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/aphelion-check.XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT

# Keep headless checks separate from the player's saved progress.
export XDG_DATA_HOME="$check_dir/data"
export XDG_CONFIG_HOME="$check_dir/config"
export XDG_CACHE_HOME="$check_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

run_check() {
    local name="$1"
    shift
    printf 'Checking %s...\n' "$name"
    "$project_dir/tools/run.sh" "$@" 2>&1 | tee "$check_dir/$name.log"
    if rg -q 'SCRIPT ERROR:|Parse Error:|ERROR:' "$check_dir/$name.log"; then
        printf 'Godot reported an error during %s.\n' "$name" >&2
        return 1
    fi
}

run_check import --headless --editor --quit
run_check gameplay --headless --quit-after 600 -- --smoke-test
if ! rg -q '^PASS: workshop, assembly, rollout, ignition, ascent, map, pause, return' "$check_dir/gameplay.log"; then
    printf '%s\n' 'The gameplay smoke check did not complete.' >&2
    exit 1
fi
run_check flight --headless --script res://tests/test_flight.gd
run_check game_loop --headless --script res://tests/test_gameplay.gd
run_check profile --headless --script res://tests/test_profile.gd
run_check craft --headless --script res://tests/test_craft.gd
run_check builder --headless --script res://tests/test_builder.gd
run_check planet --headless --script res://tests/test_planet_surface.gd
run_check planet_bake --headless --script res://tests/test_planet_bake.gd
run_check terrain_landings --headless --script res://tests/test_terrain_landings.gd
printf '%s\n' 'All available checks passed.'
