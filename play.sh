#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
version_file="$project_dir/build/LATEST"
if [[ ! -f "$version_file" ]]; then
    printf '%s\n' 'No packaged release is selected. Export the game and run python3 tools/package_builds.py first.' >&2
    exit 1
fi
IFS= read -r game_version < "$version_file" || true
if [[ ! "$game_version" =~ ^[[:alnum:]][[:alnum:]._-]*$ || "$game_version" == *..* ]]; then
    printf '%s\n' 'The packaged release version is invalid.' >&2
    exit 1
fi
game_dir="$project_dir/build/$game_version/linux"
if [[ ! -x "$game_dir/APHELION.x86_64" || ! -f "$game_dir/APHELION.pck" ]]; then
    printf 'Aphelion %s is missing its executable or data pack. Re-export and package this release.\n' "$game_version" >&2
    exit 1
fi
# Resolve both files from one version directory, regardless of launch location.
cd -- "$game_dir"
exec "$game_dir/APHELION.x86_64" "$@"
