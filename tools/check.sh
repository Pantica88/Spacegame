#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/aphelion-check.XXXXXX")"
check_pid=""
trap 'if [[ -n "$check_pid" ]]; then kill "$check_pid" 2>/dev/null || true; fi; rm -rf -- "$check_dir"' EXIT

run_check() {
    local name="$1"
    shift
    local xdg log code=0 error_seen=""
    xdg="$(mktemp -d "$check_dir/$name.XXXXXX")"
    log="$check_dir/$name.log"
    # Each process gets fresh storage, including subprocesses it launches.
    export XDG_DATA_HOME="$xdg/data"
    export XDG_CONFIG_HOME="$xdg/config"
    export XDG_CACHE_HOME="$xdg/cache"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    printf 'Checking %s...\n' "$name"
    # The monitor can run before the background shell opens its redirection.
    : > "$log"
    timeout --kill-after=2s 1800 "$project_dir/tools/run.sh" "$@" > "$log" 2>&1 &
    check_pid=$!
    # An assertion aborts the test method before quit(), leaving SceneTree
    # alive. Allow the backtrace to finish, then stop the entire process group.
    while kill -0 "$check_pid" 2>/dev/null; do
        if [[ -z "$error_seen" ]] && rg -q 'SCRIPT ERROR:|Parse Error:' "$log"; then
            error_seen=$SECONDS
        fi
        if [[ -n "$error_seen" ]] && (( SECONDS - error_seen >= 2 )); then
            kill "$check_pid" 2>/dev/null || true
            break
        fi
        sleep 0.2
    done
    wait "$check_pid" || code=$?
    check_pid=""
    cat "$log"
    if rg -q 'SCRIPT ERROR:|Parse Error:|ERROR:' "$log"; then
        printf 'Godot reported an error during %s.\n' "$name" >&2
        return 1
    fi
    return "$code"
}

run_check import --headless --editor --quit
run_check gameplay --headless --quit-after 600 -- --smoke-test
if ! rg -q '^PASS: workshop, assembly, rollout, ignition, ascent, map, pause, return' "$check_dir/gameplay.log"; then
    printf '%s\n' 'The gameplay smoke check did not complete.' >&2
    exit 1
fi
run_check launch_warmup --headless --script res://tests/test_launch_warmup.gd
run_check launch_complex --headless --script res://tests/test_launch_complex.gd
run_check equatorial_launch --headless --script res://tests/test_equatorial_launch.gd
run_check launch_contact --headless --script res://tests/test_launch_contact.gd
run_check flight_audio --headless --script res://tests/test_flight_audio.gd
run_check navball --headless --script res://tests/test_navball.gd
run_check maneuver_math --headless --script res://tests/test_maneuver_plan.gd
run_check maneuver_map --headless --script res://tests/test_maneuver_map.gd
run_check orbit_interaction --headless --script res://tests/test_orbit_interaction.gd
run_check orbit_mouse --headless --script res://tests/test_orbit_mouse.gd
run_check map_focus_precision --headless --script res://tests/test_map_focus_precision.gd
run_check orbital_map --headless --script res://tests/test_orbital_map.gd
run_check sun --headless --script res://tests/test_sun.gd
run_check eight_boosters --headless --script res://tests/benchmark_eight_boosters.gd
run_check radial_engines --headless --script res://tests/benchmark_radial_engines.gd
run_check separator_snap --headless --script res://tests/benchmark_separator_snap.gd
run_check side_stack_drag --headless --script res://tests/benchmark_side_stack_drag.gd
run_check large_workshop --headless --script res://tests/benchmark_large_workshop.gd
run_check large_flight --headless --script res://tests/benchmark_large_craft_flight.gd
run_check vehicle_batching --headless --script res://tests/test_vehicle_batching.gd
run_check geometry_cache --headless --script res://tests/test_geometry_cache.gd
run_check titan_game_loop --headless --script res://tests/benchmark_titan_game_loop.gd
run_check time_warp --headless --script res://tests/test_time_warp.gd
run_check space_moons --headless --script res://tests/test_space_moons.gd
run_check flight --headless --script res://tests/test_flight.gd
run_check engine_cutoff --headless --script res://tests/test_engine_cutoff.gd
run_check thrust_weight --headless --script res://tests/test_thrust_weight.gd
run_check atmospheric_entry --headless --script res://tests/test_atmospheric_entry.gd
run_check atmospheric_coast --headless --script res://tests/test_atmospheric_coast.gd
run_check turn_drag --headless --script res://tests/test_turn_drag.gd
run_check flight_interpolation --headless --script res://tests/test_flight_interpolation.gd
run_check aerothermal_visuals --headless --script res://tests/test_aerothermal_visuals.gd
run_check flame_cloud_overlap --headless --script res://tests/test_flame_cloud_overlap.gd
run_check plasma_preview --headless --script res://tests/test_plasma_preview.gd
run_check distant_debris --headless --script res://tests/test_distant_debris.gd
run_check detached_physics --headless --script res://tests/test_detached_physics.gd
run_check body_collisions --headless --script res://tests/test_body_collisions.gd
run_check game_loop --headless --script res://tests/test_gameplay.gd
run_check profile --headless --script res://tests/test_profile.gd
run_check reaction_wheel --headless --script res://tests/test_reaction_wheel.gd
run_check craft --headless --script res://tests/test_craft.gd
run_check part_capacity --headless --script res://tests/test_part_capacity.gd
run_check stage_blocks --headless --script res://tests/test_stage_blocks.gd
run_check multistage --headless --script res://tests/test_multistage.gd
run_check parachute --headless --script res://tests/test_parachute.gd
run_check parachute_staging --headless --script res://tests/test_parachute_staging.gd
run_check parachute_cloth --headless --script res://tests/test_parachute_cloth.gd
run_check parachute_visual_clock --headless --script res://tests/test_parachute_visual_clock.gd
run_check parachute_sleep --headless --script res://tests/test_parachute_sleep.gd
run_check parachute_drape --headless --script res://tests/test_parachute_drape.gd
run_check parachute_relief --headless --script res://tests/test_parachute_relief.gd
run_check parachute_attitude --headless --script res://tests/test_parachute_attitude.gd
run_check parachute_cutaway --headless --script res://tests/test_parachute_cutaway.gd
run_check water_landing --headless --script res://tests/test_water_landing.gd
run_check vessel_settling --headless --script res://tests/test_vessel_settling.gd
run_check hillside_recovery --headless --script res://tests/benchmark_hillside_recovery.gd
run_check cap_tether --headless --script res://tests/test_cap_tether.gd
run_check radial_mass --headless --script res://tests/test_radial_mounts.gd
run_check radial_builder --headless --script res://tests/test_radial_builder.gd
run_check radial_tanks --headless --script res://tests/test_radial_tanks.gd
run_check symmetry_removal --headless --script res://tests/test_symmetry_removal.gd
run_check nested_separators --headless --script res://tests/test_nested_separators.gd
run_check lower_side_stage --headless --script res://tests/test_lower_side_stage.gd
run_check tall_rockets --headless --script res://tests/test_tall_rockets.gd
run_check workshop_camera --headless --script res://tests/test_workshop_camera.gd
run_check builder --headless --script res://tests/test_builder.gd
run_check rollout --headless --script res://tests/test_rollout.gd
run_check sparrow_asset --headless --script res://tests/test_sparrow_asset.gd
run_check planet --headless --script res://tests/test_planet_surface.gd
run_check planet_detail --headless --script res://tests/test_planet_detail.gd
run_check planet_preview --headless --script res://tests/test_planet_preview.gd
run_check planet_camera --headless --script res://tests/test_planet_camera.gd
run_check planet_editor --headless --script res://tests/test_planet_editor.gd
run_check planet_bake --headless --script res://tests/test_planet_bake.gd
run_check planet_bake_storage --headless --script res://tests/test_planet_bake_storage.gd
run_check cloud_painting --headless --script res://tests/test_cloud_painting.gd
run_check cloud_occupancy --headless --script res://tests/test_cloud_occupancy.gd
run_check cloud_editor --headless --script res://tests/test_cloud_editor.gd
run_check cloud_save --headless --script res://tests/test_cloud_save_persistence.gd
run_check cloud_vessel_light --headless --script res://tests/test_cloud_vessel_light.gd
run_check terrain_landings --headless --script res://tests/test_terrain_landings.gd
printf '%s\n' 'All available checks passed.'
