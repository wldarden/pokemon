#!/usr/bin/env python3
"""Phase 2d: extract the Pokémon Center exterior sprite from the Buildings
sheet and the Pokémon Center interior from the pre-rendered Maps sheet.

Outputs:
  - assets/buildings/frlg/pc_exterior.png
      96x70, transparent background (chroma-keyed from sheet white).
  - assets/maps/frlg/pc_interior.png
      240x160, single-screen FR/LG PC interior, ready as a TextureRect
      background for PokemonCenter.tscn.

Coordinates were measured against the Spriters Resource rips:
  Buildings.png ........ "Pokemon Center" label at (~520, 248). Sprite
                         body spans x=496..592, y=244..314.
  Pokemon Center _ Mart.png .... "Pokemon Center (1F)" panel, 240x160
                                 interior at (0, 16, 240, 176).

Mart + Pokemart interior coords are recorded as comments for future phases.
"""

from __future__ import annotations
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC_BUILDINGS = REPO / "assets" / "Pokemon Sprites" / (
    "Game Boy Advance - Pokemon FireRed _ LeafGreen - Tilesets - Buildings.png"
)
SRC_MAPS = REPO / "assets" / "Pokemon Sprites" / (
    "Game Boy Advance - Pokemon FireRed _ LeafGreen - "
    "Maps (Towns, Buildings, Etc.) - Pokemon Center _ Mart.png"
)

OUT_BUILDINGS_DIR = REPO / "assets" / "buildings" / "frlg"
OUT_MAPS_DIR = REPO / "assets" / "maps" / "frlg"

# ---- Crop rectangles ------------------------------------------------------
PC_EXTERIOR_RECT = (496, 244, 592, 314)   # Buildings.png
# Initial crop was (0, 16, 240, 176) — had 8 extra source pixels on the left
# and 8 on the top while missing 8 on the right. Shifted the window right + down
# by 8 to re-center on the actual interior art.
PC_INTERIOR_RECT = (8,   24,  248, 184)   # Pokemon Center _ Mart.png → 240×160

# Future-phase rectangles (not extracted now):
#   MART_EXTERIOR_RECT = (416, 244, 496, 314)   # blue-roofed MART
#   POKEMART_INTERIOR_RECT = (256, 16, 496, 176)  # right half of the Maps sheet

# Sheet background is near-white; treat as chroma-key for exterior only.
WHITE_BG = (255, 255, 255)
CHROMA_TOLERANCE = 6


def strip_white(img: Image.Image) -> Image.Image:
    """Convert near-white pixels to transparent (for building exterior sprite)."""
    out = img.convert("RGBA").copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if (abs(r - WHITE_BG[0]) <= CHROMA_TOLERANCE
                and abs(g - WHITE_BG[1]) <= CHROMA_TOLERANCE
                and abs(b - WHITE_BG[2]) <= CHROMA_TOLERANCE):
                px[x, y] = (0, 0, 0, 0)
    return out


def main() -> int:
    OUT_BUILDINGS_DIR.mkdir(parents=True, exist_ok=True)
    OUT_MAPS_DIR.mkdir(parents=True, exist_ok=True)

    # Exterior: crop + chroma-key white.
    bld = Image.open(SRC_BUILDINGS)
    pc_ext = bld.crop(PC_EXTERIOR_RECT)
    pc_ext = strip_white(pc_ext)
    pc_ext_path = OUT_BUILDINGS_DIR / "pc_exterior.png"
    pc_ext.save(pc_ext_path)
    print(f"PC exterior: {pc_ext.size} -> {pc_ext_path.relative_to(REPO)}")

    # Interior: straight crop. No chroma-key.
    maps = Image.open(SRC_MAPS)
    pc_int = maps.crop(PC_INTERIOR_RECT)
    pc_int_path = OUT_MAPS_DIR / "pc_interior.png"
    pc_int.save(pc_int_path)
    print(f"PC interior: {pc_int.size} -> {pc_int_path.relative_to(REPO)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
