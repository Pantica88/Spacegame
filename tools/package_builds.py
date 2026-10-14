#!/usr/bin/env python3
"""Package existing Godot release exports and source; this does not run exports.

Run from any directory with Python 3.9+: python3 tools/package_builds.py
Use --check-only to validate inputs without changing build artifacts.
Validated versioned packages also update build/linux, build/windows, the ZIPs
directly under build/, and build/LATEST. Use --no-update-current to opt out.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import zipfile


SOURCE_FILES = (
    ".gitignore",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "project.godot",
    "export_presets.cfg",
    "play.sh",
)
SOURCE_DIRS = ("assets", "scenes", "scripts", "tests", "tools", "docs")
EXCLUDED_NAMES = {
    ".git", ".godot", ".agents", ".codex", ".DS_Store", "__pycache__",
    ".pytest_cache", "build", "exports", "export_credentials.cfg",
}
EXCLUDED_SUFFIXES = {".log", ".tmp", ".pyc", ".pyo", ".swp", ".bak"}
PLATFORMS = (
    (
        "linux",
        "APHELION.x86_64",
        "Run `APHELION.x86_64` from a graphical Linux desktop. If your extractor "
        "removes its executable permission, run `chmod +x APHELION.x86_64`, "
        "then `./APHELION.x86_64`.",
    ),
    (
        "windows",
        "APHELION.exe",
        "Double-click `APHELION.exe` on a Windows x86-64 desktop.",
    ),
)
PACKAGE_NAMES = tuple(f"APHELION-{platform}-x86_64.zip" for platform, _, _ in PLATFORMS) + (
    "APHELION-source.zip",
)

PLAYER_README = """# APHELION — Flight Works

Build a rocket. Fly it yourself. Bring something home.

This is the playable {version} prototype of an original 3D rocket-building game. APHELION is a working title. It is a foundation for a future commercial game and is not a finished Steam release.

## Start

{launch}

Keep the executable and `APHELION.pck` together. Godot does not need to be installed to play this build.

## Build and stage

In the workshop **Parts** tab, choose **New** for an empty indoor assembly bay. Only the capsule starts unlocked. Drag it into the bay, then add each newly unlocked part by moving it near a compatible connection surface. The held 3D part is red while invalid, snaps and turns green near a compatible surface, and attaches when released. Select tanks to rotate with **R**, duplicate with **Ctrl+D**, or delete. **Undo/Redo** also covers staging edits. In the right-hand **Stages** column, drag actions between groups and reorder groups using their headers or arrows. Space executes one group; unsafe parachute stages wait until safe descent. The **Flight checks** tab contains the mission selector and launch checks. **Save design** stores connected parts and their stage sequence.

## First flight

1. Choose two tanks, the Sparrow engine, fins on, and boosters off. Select **A little altitude** and roll out to the launch pad.
2. Keep stability assistance on and time at 1×. Press **Space** to ignite at full throttle and fly straight up.
3. At about 1.2 km altitude, press **Space** to separate the capsule. It will coast up and then descend.
4. While descending below 2.5 km and at 180 m/s or less, press **P** for the parachute. Wait for a safe landing and return to the workshop.

## Controls

| Input | Action |
| --- | --- |
| W / S | Pitch |
| A / D | Yaw |
| Q / E | Roll |
| Shift / Ctrl | Increase / decrease throttle |
| Z / X | Full throttle / cut throttle |
| Space | Ignite, jettison boosters, or separate capsule |
| P | Deploy parachute inside the safe envelope |
| T | Toggle stability assistance |
| M | Orbital map |
| . | Cycle 1×, 3×, 8× time |
| Esc | Pause, sound setting, credits, or quit |
| F11 | Fullscreen |
| Right mouse drag / wheel | Orbit camera / zoom |

## Try an orbit

Use the same starter design with stability assistance on and time at 1×. Launch upright at full throttle, then cut with **X** when **APOAPSIS** reaches about 45 km. Coast upright above 18 km **ALTITUDE**. Use **D** to turn toward **0° UP** on the attitude display and small **A/D** taps to stay horizontal. When upward **VERTICAL SPEED** falls below about 70 m/s, press **Z**. Keep the engine attached and maintain a horizontal heading. Cut with **X** as **PERIAPSIS** rises above 18 km and the orbital contract completes. Use **M** to inspect the coast.

This ascent profile is exercised by the flight simulation tests using continuous steering adjustments; manual steering takes practice. The orbit contract does not require recovery. Retain your engine and fuel if you want to attempt a later return.

## Progress and credits

The game saves your latest design, flight records, and completed contracts locally. It does not save an active flight for later resumption. The pause menu contains sound and fullscreen controls and engine credits.

The initial content uses procedural meshes, project-authored graphics, and generated engine audio. The game runs on Godot 4.7.2; its license and complete engine component notices are included in **THIRD_PARTY_NOTICES.md**.
"""


def require_file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing, empty, or symlinked input: {path}")


def project_version(project):
    """Read Godot's version string without interpreting its other Variant values."""
    application_section = False
    for line in (project / "project.godot").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("["):
            application_section = line == "[application]"
        if not application_section or not re.match(r"config/version\s*=", line):
            continue
        match = re.fullmatch(r'config/version\s*=\s*"([A-Za-z0-9][A-Za-z0-9._-]*)"\s*(?:;.*)?', line)
        if match is None:
            raise ValueError("config/version must be a nonempty filename-safe version string")
        return match.group(1)
    return None


def source_files(project):
    """Only include reviewed project roots; never sweep the entire workspace."""
    files = []
    for name in SOURCE_FILES:
        path = project / name
        require_file(path)
        files.append(path)
    for name in SOURCE_DIRS:
        folder = project / name
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError(f"Missing or symlinked source directory: {folder}")
        for path in sorted(folder.rglob("*")):
            relative = path.relative_to(project)
            if any(part in EXCLUDED_NAMES for part in relative.parts):
                continue
            if path.suffix in EXCLUDED_SUFFIXES or path.name.endswith("~"):
                continue
            if path.is_symlink():
                raise ValueError(f"Source symlinks are not packaged: {path}")
            if path.is_file():
                files.append(path)
    return files


def add_file(archive, path, archive_name, executable=False):
    # Store POSIX permissions explicitly, even when packaging on Windows.
    info = zipfile.ZipInfo.from_file(path, arcname=archive_name)
    mode = 0o755 if executable or path.stat().st_mode & 0o111 else 0o644
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | mode) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    # Streaming avoids loading the large exported engine into memory.
    with path.open("rb") as source, archive.open(info, "w") as target:
        shutil.copyfileobj(source, target)


def check_archive(path, expected_names, executable_name=None):
    with zipfile.ZipFile(path) as archive:
        if archive.namelist() != expected_names:
            raise ValueError(f"Unexpected archive contents: {path}")
        failed = archive.testzip()
        if failed is not None:
            raise ValueError(f"Archive CRC check failed: {path}: {failed}")
        if executable_name is not None:
            mode = archive.getinfo(executable_name).external_attr >> 16
            if not mode & stat.S_IXUSR:
                raise ValueError(f"Linux executable permission missing: {path}")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def current_release_path(build_root, release, version):
    """LATEST is a version, not an arbitrary path consumed by the launcher."""
    if version is None or re.fullmatch(
        r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
        r"(?:-[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)?"
        r"(?:\+[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)?", version,
    ) is None:
        raise ValueError("Updating current builds requires a semantic config/version")
    if release.resolve() != (build_root / version).resolve():
        raise ValueError("Current builds must be packaged in build/<config/version>; "
                         "use --no-update-current for another output directory")


def same_export(first, second):
    """Avoid recopying/archiving an unchanged current directory on Windows."""
    if not first.is_dir() or first.is_symlink():
        return False
    first_files = sorted(path.relative_to(first) for path in first.rglob("*"))
    second_files = sorted(path.relative_to(second) for path in second.rglob("*"))
    if first_files != second_files:
        return False
    for relative in second_files:
        left, right = first / relative, second / relative
        if left.is_symlink() or right.is_symlink() or left.is_dir() != right.is_dir():
            return False
        if right.is_file() and sha256(left) != sha256(right):
            return False
    return True


def publish_current(build_root, release, version, use_symlinks=None):
    """Publish familiar launch/download paths without modifying old engine files.

    POSIX directory links switch atomically. Platforms without directory symlink
    support receive staged directory copies. Previously physical directories are
    moved to build/archive, so running processes retain their executable/PCK.
    Every input is validated and staged before publication. LATEST changes last.
    """
    current_release_path(build_root, release, version)
    if use_symlinks is None:
        use_symlinks = os.name != "nt"
    for platform, executable, _ in PLATFORMS:
        for name in (executable, "APHELION.pck", "README.md", "THIRD_PARTY_NOTICES.md"):
            require_file(release / platform / name)
    for name in (*PACKAGE_NAMES, "SHA256SUMS.txt"):
        require_file(release / name)
    expected_checksums = "".join(f"{sha256(release / name)}  {name}\n" for name in PACKAGE_NAMES)
    if (release / "SHA256SUMS.txt").read_text(encoding="ascii") != expected_checksums:
        raise ValueError("Release checksums do not match; current builds were not changed")
    for name in PACKAGE_NAMES:
        with zipfile.ZipFile(release / name) as archive:
            if archive.testzip() is not None:
                raise ValueError(f"Release archive failed CRC validation: {name}")

    with tempfile.TemporaryDirectory(prefix=".current-", dir=build_root) as temporary:
        staging = Path(temporary)
        changes = []
        for platform, _, _ in PLATFORMS:
            destination = build_root / platform
            if destination.is_symlink() and destination.resolve() == (release / platform).resolve():
                continue
            if not use_symlinks and same_export(destination, release / platform):
                continue
            staged = staging / platform
            if use_symlinks:
                staged.symlink_to(Path(version) / platform, target_is_directory=True)
            else:
                shutil.copytree(release / platform, staged)
            changes.append((staged, destination))
        for name in (*PACKAGE_NAMES, "SHA256SUMS.txt"):
            destination = build_root / name
            if destination.is_file() and not destination.is_symlink() and sha256(destination) == sha256(release / name):
                continue
            staged = staging / name
            shutil.copy2(release / name, staged)
            changes.append((staged, destination))
        latest = staging / "LATEST"
        latest.write_text(f"{version}\n", encoding="ascii")
        if not (build_root / "LATEST").is_file() or (build_root / "LATEST").read_bytes() != latest.read_bytes():
            changes.append((latest, build_root / "LATEST"))

        # Prepare all rollback copies before moving any current entry. Engine
        # directories themselves are archived by rename, never copied over.
        backups = staging / "previous"
        backups.mkdir()
        archive_directory = None
        previous = {}
        for _, destination in changes:
            if destination.is_symlink():
                backup = backups / destination.name
                backup.symlink_to(os.readlink(destination), target_is_directory=True)
                previous[destination] = backup
            elif destination.is_file():
                backup = backups / destination.name
                shutil.copy2(destination, backup)
                previous[destination] = backup
            elif destination.exists():
                if not destination.is_dir():
                    raise ValueError(f"Unexpected current build entry: {destination}")
                if archive_directory is None:
                    archive_root = build_root / "archive"
                    archive_root.mkdir(exist_ok=True)
                    archive_directory = Path(tempfile.mkdtemp(prefix=f"pre-{version}-", dir=archive_root))
                previous[destination] = archive_directory / destination.name
            else:
                previous[destination] = None

        applied = []
        try:
            for staged, destination in changes:
                backup = previous[destination]
                if destination.is_dir() and not destination.is_symlink():
                    destination.replace(backup)
                    applied.append(destination)
                    staged.replace(destination)
                else:
                    staged.replace(destination)
                    applied.append(destination)
        except OSError:
            # Restore previous paths if any rename fails (for example a locked
            # Windows directory). Preserve newly installed directories too.
            for destination in reversed(applied):
                if destination.is_dir() and not destination.is_symlink():
                    if archive_directory is None:
                        archive_root = build_root / "archive"
                        archive_root.mkdir(exist_ok=True)
                        archive_directory = Path(tempfile.mkdtemp(prefix=f"pre-{version}-", dir=archive_root))
                    destination.replace(archive_directory / f"unpublished-{destination.name}")
                elif destination.exists() or destination.is_symlink():
                    destination.unlink()
                backup = previous[destination]
                if backup is not None:
                    backup.replace(destination)
            raise
        if archive_directory is not None:
            print(f"Previous physical exports preserved in {archive_directory}")
        print(f"Current release: {version} (build/LATEST and familiar launch/download paths)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-dir", type=Path, default=Path(__file__).resolve().parent.parent,
        help="project root (defaults to the parent of this script's tools directory)",
    )
    parser.add_argument(
        "--build-dir", type=Path,
        help="export and package directory; relative paths resolve from the project root "
             "(default: build/<config/version>, or build when the version is absent)",
    )
    parser.add_argument(
        "--check-only", action="store_true",
        help="validate all source and exported inputs without writing packages",
    )
    parser.add_argument(
        "--no-update-current", action="store_true",
        help="package only the selected output directory, without updating build/LATEST or current paths",
    )
    args = parser.parse_args()
    project = args.project_dir.resolve()
    sources = source_files(project)
    version = project_version(project)
    if args.build_dir is not None:
        build = (project / args.build_dir).resolve()
    else:
        build = project / "build"
        if version is not None:
            build /= version
    if not args.no_update_current:
        current_release_path(project / "build", build, version)
    for platform, executable, _ in PLATFORMS:
        for name in (executable, "APHELION.pck"):
            require_file(build / platform / name)
    if args.check_only:
        print(f"Inputs valid: {len(sources)} source files and both desktop exports.")
        return

    # Validate every staged ZIP before replacing any previously packaged build.
    with tempfile.TemporaryDirectory(prefix=".package-", dir=build) as temporary:
        staging = Path(temporary)
        packages = []
        for platform, executable, launch in PLATFORMS:
            package_name = f"APHELION-{platform}-x86_64"
            archive_path = staging / f"{package_name}.zip"
            readme_path = staging / f"{platform}-README.md"
            readme_path.write_text(
                PLAYER_README.format(launch=launch, version=version or "unversioned"),
                encoding="utf-8",
            )
            inputs = (
                (build / platform / executable, executable),
                (build / platform / "APHELION.pck", "APHELION.pck"),
                (readme_path, "README.md"),
                (project / "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.md"),
            )
            expected = [f"{package_name}/{name}" for _, name in inputs]
            with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for source, name in inputs:
                    add_file(archive, source, f"{package_name}/{name}", platform == "linux" and name == executable)
            check_archive(archive_path, expected, expected[0] if platform == "linux" else None)
            packages.append(archive_path)

        archive_path = staging / "APHELION-source.zip"
        expected = [f"APHELION-source/{path.relative_to(project).as_posix()}" for path in sources]
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for source, name in zip(sources, expected):
                add_file(archive, source, name)
        check_archive(archive_path, expected)
        packages.append(archive_path)
        checksums = staging / "SHA256SUMS.txt"
        checksums.write_text(
            "".join(f"{sha256(path)}  {path.name}\n" for path in packages), encoding="ascii",
        )
        # Keep quick-start documentation beside the unpackaged exports as well.
        for platform, _, _ in PLATFORMS:
            shutil.copy2(staging / f"{platform}-README.md", build / platform / "README.md")
            shutil.copy2(project / "THIRD_PARTY_NOTICES.md", build / platform / "THIRD_PARTY_NOTICES.md")
        for path in [*packages, checksums]:
            destination = build / path.name
            path.replace(destination)
            print(f"{destination}: {destination.stat().st_size:,} bytes")
    if not args.no_update_current:
        publish_current(project / "build", build, version)


if __name__ == "__main__":
    main()
