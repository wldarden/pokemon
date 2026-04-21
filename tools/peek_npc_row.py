#!/usr/bin/env python3
"""Crop one character's row-block from the FR/LG NPC sprite sheet.

The full sheet is 238x2967 — too big to eyeball. This pulls a single 33-px
row-block (one character) out so it can be inspected or read into an LLM
context without loading the whole sheet.

Geometry matches tools/build_npc_atlas.py:
  GRID_Y0 = 42, STRIDE_Y = 33.
For character at `index`:
  y0 = 42 + index * 33
  y1 = 42 + (index + count) * 33

Usage:
  tools/peek_npc_row.py 0                 # row 0, one 33-px block
  tools/peek_npc_row.py 0 --count 2       # two stacked row-blocks (66 px)
  tools/peek_npc_row.py 5 --out /tmp/x.png
  tools/peek_npc_row.py 5 --zoom 4        # 4x nearest-neighbor upscaled copy
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets" / "Pokemon Sprites" / (
    "Game Boy Advance - Pokemon FireRed _ LeafGreen - "
    "Trainers & Non-Playable Characters - Overworld NPCs.png"
)

GRID_Y0 = 42
STRIDE_Y = 25  # each character row-block is 24 px tall + 1 px gutter


def crop_row(index: int, count: int = 1) -> Image.Image:
    img = Image.open(SRC)
    y0 = GRID_Y0 + index * STRIDE_Y
    y1 = GRID_Y0 + (index + count) * STRIDE_Y
    if y1 > img.height:
        raise SystemExit(
            f"index {index} + count {count} exceeds sheet height "
            f"({y1} > {img.height})"
        )
    return img.crop((0, y0, img.width, y1))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("index", type=int, help="Character row index (0-based).")
    ap.add_argument("--count", type=int, default=1, help="Row-blocks to include (default 1).")
    ap.add_argument("--out", default=None, help="Output path. Default: /tmp/npc_row_<index>.png")
    ap.add_argument("--zoom", type=int, default=1, help="Nearest-neighbor upscale factor (default 1).")
    args = ap.parse_args()

    strip = crop_row(args.index, args.count)
    if args.zoom > 1:
        strip = strip.resize(
            (strip.width * args.zoom, strip.height * args.zoom),
            Image.NEAREST,
        )

    out = Path(args.out) if args.out else Path(f"/tmp/npc_row_{args.index}.png")
    strip.save(out)
    print(f"Saved {strip.width}x{strip.height} strip: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
