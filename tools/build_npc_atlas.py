#!/usr/bin/env python3
"""
Extract characters from the ripped FR/LG Overworld NPCs sheet into a clean
per-character PNG + a combined preview atlas.

Source file layout (Spriters Resource "Overworld NPCs.png"):
  - 238×2967 px sheet with outer border + "Characters" title bar.
  - Grid starts at (9, 42). Tile stride is 17 px horizontal, 25 px vertical.
  - Each tile is 16 wide × 24 tall, containing the full character sprite
    (head at top, feet at bottom) with a 1-px gutter between tiles on
    both axes. At most 13 tiles per row.
  - Background color per tile is either orange (255,127,39) or green
    (~0,180,0) — acts as a chroma-key and is stripped to alpha.

Row types (number of tiles per row):
  - Standing only:      4 tiles  -> [SS, SN, SW, SE]
  - Walking:           12 tiles  -> per-direction [R1, S, R2] × [S, N, W, E]
  - Walking + gesture: 13 tiles  -> walking 12 + one gesture frame

We unify all rows into a 13-column layout so atlas column semantics are fixed:

  col 0: R1S   col 3: R1N   col 6: R1W   col 9:  R1E   col 12: gesture
  col 1: SS    col 4: SN    col 7: SW    col 10: SE
  col 2: R2S   col 5: R2N   col 8: R2W   col 11: R2E

For standing-only rows, the 4 source tiles fill cols 1/4/7/10 (the stand
frames), and the other cols stay transparent.

Config `CHARACTERS` below maps row_index -> (name, row_type). Edit as you
identify rows. Row indices are 0-based starting at the first tile row.
"""

from __future__ import annotations
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets" / "Pokemon Sprites" / "Game Boy Advance - Pokemon FireRed _ LeafGreen - Trainers & Non-Playable Characters - Overworld NPCs.png"
OUT_DIR = REPO / "assets" / "sprites" / "trainers" / "frlg"
PREVIEW_PATH = Path("/tmp/npc_atlas_preview.png")

# Grid geometry (verified by pixel scan).
GRID_X0 = 9
GRID_Y0 = 42
TILE_W = 16
TILE_H = 24
STRIDE_X = 17
STRIDE_Y = 25

# Background colors to strip (tolerance=12 per channel).
# Sampled from the source sheet — some tiles are on orange, some on green.
# Both are treated as transparent chroma-key.
CHROMA_KEYS = [
    (255, 127, 39),   # orange
    (34, 177, 76),    # green
]
CHROMA_TOLERANCE = 12

# Column indices for the 13-col unified layout.
COL_R1S, COL_SS, COL_R2S = 0, 1, 2
COL_R1N, COL_SN, COL_R2N = 3, 4, 5
COL_R1W, COL_SW, COL_R2W = 6, 7, 8
COL_R1E, COL_SE, COL_R2E = 9, 10, 11
COL_GESTURE = 12

# Row types.
WALK = "walk"            # 12-tile row, cols 0-11 map directly
WALK_GESTURE = "walk_g"  # 13-tile row, cols 0-12 map directly
STAND = "stand"          # 4-tile row: SS, SN, SW, SE → cols 1, 4, 7, 10

# ---- The catalogue ---------------------------------------------------------
#
# User-confirmed rows 0-4. Rows 5+ are guessed as WALK for a first-pass scrape.
# User noted: 26 consecutive "normal" rows, then a weird single-tile row, then
# 35 more normal rows, then 3 biker rows (skip — double-wide, non-standard),
# then 21 more normal rows. We extract rows 0-25 in this first pass; later
# batches can extend.
#
# Format: (row_index_in_sheet, name, row_type)
CHARACTERS = [
    (0, "player_m",      WALK),
    (1, "player_f",      WALK),
    (2, "rival",         WALK),
    (3, "oak",           WALK),
    (4, "mom",           STAND),
]
# Auto-fill rows 5-25 as generic trainer sprites (walk-only, no gesture) —
# these are placeholders; rename in config once identified.
for i in range(5, 26):
    CHARACTERS.append((i, f"npc_{i:03d}", WALK))


def strip_chroma(img: Image.Image) -> Image.Image:
    """Return a copy of `img` with chroma-key colors replaced by transparency."""
    out = img.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            for kr, kg, kb in CHROMA_KEYS:
                if (abs(r - kr) <= CHROMA_TOLERANCE
                    and abs(g - kg) <= CHROMA_TOLERANCE
                    and abs(b - kb) <= CHROMA_TOLERANCE):
                    px[x, y] = (0, 0, 0, 0)
                    break
    return out


def tile_at(src: Image.Image, col: int, row: int) -> Image.Image:
    """Extract a single (col, row) tile from the source sheet."""
    x = GRID_X0 + col * STRIDE_X
    y = GRID_Y0 + row * STRIDE_Y
    return src.crop((x, y, x + TILE_W, y + TILE_H))


def _is_chroma(px: tuple) -> bool:
    r, g, b = px[0], px[1], px[2]
    for kr, kg, kb in CHROMA_KEYS:
        if (abs(r - kr) <= CHROMA_TOLERANCE
            and abs(g - kg) <= CHROMA_TOLERANCE
            and abs(b - kb) <= CHROMA_TOLERANCE):
            return True
    return False


def tile_present(src: Image.Image, col: int, row: int) -> bool:
    """True iff a tile exists at (col, row) — detected by chroma-key bg at its corner.

    Rows that only hold 4 STAND tiles have sheet-white (255,255,255) past col 3,
    so their top-left corners won't match either chroma key.
    """
    x = GRID_X0 + col * STRIDE_X
    y = GRID_Y0 + row * STRIDE_Y
    return _is_chroma(src.getpixel((x, y)))


def detect_row_type(src: Image.Image, row: int) -> str:
    """Classify a row as STAND (4 tiles), WALK (12), or WALK_GESTURE (13)."""
    if not tile_present(src, 4, row):
        return STAND
    if tile_present(src, 12, row):
        return WALK_GESTURE
    return WALK


def build_row(src: Image.Image, row_idx: int, row_type: str) -> Image.Image:
    """Build a single-character 13-col wide output row (16*13 = 208 px wide, 32 tall)."""
    out = Image.new("RGBA", (TILE_W * 13, TILE_H), (0, 0, 0, 0))
    if row_type == WALK:
        for c in range(12):
            t = strip_chroma(tile_at(src, c, row_idx))
            out.paste(t, (c * TILE_W, 0), t)
    elif row_type == WALK_GESTURE:
        for c in range(13):
            t = strip_chroma(tile_at(src, c, row_idx))
            out.paste(t, (c * TILE_W, 0), t)
    elif row_type == STAND:
        # 4 source tiles (SS, SN, SW, SE) land in cols 1, 4, 7, 10.
        for src_c, dst_c in [(0, COL_SS), (1, COL_SN), (2, COL_SW), (3, COL_SE)]:
            t = strip_chroma(tile_at(src, src_c, row_idx))
            out.paste(t, (dst_c * TILE_W, 0), t)
    return out


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    ap.add_argument(
        "--only",
        help=(
            "Extract a single character by row index (e.g. '3') or name "
            "(e.g. 'player_m'). Skips the combined preview atlas — one "
            "character per invocation keeps output small enough to read."
        ),
    )
    ap.add_argument(
        "--no-preview",
        action="store_true",
        help="Skip the combined preview atlas (implied when --only is set).",
    )
    ap.add_argument(
        "--preview-zoom",
        type=int,
        default=3,
        help="Nearest-neighbor zoom factor for the combined preview (default 3).",
    )
    args = ap.parse_args()

    chars = CHARACTERS
    if args.only is not None:
        if args.only.isdigit():
            idx = int(args.only)
            chars = [c for c in CHARACTERS if c[0] == idx]
        else:
            chars = [c for c in CHARACTERS if c[1] == args.only]
        if not chars:
            raise SystemExit(f"No character matching {args.only!r} in CHARACTERS.")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")

    # Build per-character strips.
    # Row type is auto-detected from the source — the hand-entered type in
    # CHARACTERS is treated as a hint and we warn on mismatch.
    strips = []
    for row_idx, name, declared_type in chars:
        detected_type = detect_row_type(src, row_idx)
        if detected_type != declared_type:
            print(
                f"  row {row_idx:2d} {name:12s}: "
                f"declared={declared_type!r} detected={detected_type!r} "
                f"(using detected)"
            )
        strip = build_row(src, row_idx, detected_type)
        strip.save(OUT_DIR / f"{name}.png")
        strips.append((name, strip))

    build_preview = not (args.no_preview or args.only)
    if build_preview:
        # Combined preview atlas (one row per character, labels on the left).
        from PIL import ImageDraw, ImageFont
        label_w = 80
        cell_h = TILE_H
        preview = Image.new("RGBA", (label_w + TILE_W * 13, cell_h * len(strips)), (40, 40, 60, 255))
        d = ImageDraw.Draw(preview)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 12)
        except Exception:
            font = ImageFont.load_default()
        for i, (name, strip) in enumerate(strips):
            preview.paste(strip, (label_w, i * cell_h), strip)
            d.text((4, i * cell_h + 10), name, fill=(255, 255, 255, 255), font=font)
        z = max(1, args.preview_zoom)
        preview.resize((preview.width * z, preview.height * z), Image.NEAREST).save(PREVIEW_PATH)
        print(f"Preview ({z}x zoom): {PREVIEW_PATH}")

    print(f"Extracted {len(strips)} character(s) to {OUT_DIR.relative_to(REPO)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
