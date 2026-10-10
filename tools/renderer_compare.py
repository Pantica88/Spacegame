#!/usr/bin/env python3
"""Side-by-side screenshot sheets for two perf lab runs (e.g. two renderers).

Usage: python3 tools/renderer_compare.py RUN_A RUN_B [OUTPUT_DIR]

RUN_A and RUN_B are run directories or names under build/performance/. Both
runs must use the same preset so each pair shows the same simulated moment;
capture them with ./perf.sh run --preset quick --repeats 1 --renderer ...
Writes compare-1.png (launch, dense_clouds, staging, orbit) and compare-2.png
(map, reentry, parachute, landing), RUN_A on the left. Requires Pillow.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "build" / "performance"
GROUPS = (("launch", "dense_clouds", "staging", "orbit"), ("map", "reentry", "parachute", "landing"))


def resolve(name: str) -> Path:
    path = Path(name)
    if path.is_dir():
        return path
    matches = sorted(ROOT.glob(f"*{name}"))
    if not matches:
        raise SystemExit(f"No run matching {name} in {ROOT}")
    return matches[-1]


def label(run: Path) -> str:
    config = json.loads((run / "run.json").read_text()).get("config", {})
    return f"{config.get('renderer', '?')} ({run.name.split('Z-', 1)[-1]})"


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    a, b = resolve(sys.argv[1]), resolve(sys.argv[2])
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else b
    out.mkdir(parents=True, exist_ok=True)
    for number, group in enumerate(GROUPS, 1):
        rows = []
        for scenario in group:
            left = Image.open(a / scenario / "repeat-01" / "final.png").convert("RGB")
            right = Image.open(b / scenario / "repeat-01" / "final.png").convert("RGB")
            row = Image.new("RGB", (left.width + right.width, max(left.height, right.height)))
            row.paste(left, (0, 0))
            row.paste(right, (left.width, 0))
            draw = ImageDraw.Draw(row)
            draw.text((10, 30), f"{scenario}: {label(a)}", fill=(255, 255, 0))
            draw.text((left.width + 10, 30), f"{scenario}: {label(b)}", fill=(255, 255, 0))
            rows.append(row.resize((row.width // 2, row.height // 2)))
        sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)))
        y = 0
        for row in rows:
            sheet.paste(row, (0, y))
            y += row.height
        target = out / f"compare-{number}.png"
        sheet.save(target)
        print(target)


if __name__ == "__main__":
    main()
