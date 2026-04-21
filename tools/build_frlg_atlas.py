#!/usr/bin/env python3
"""
Build the FR/LG outdoor atlas (assets/tilesets/frlg/frlg_outdoor.png) and the
corresponding TileSet resource (assets/tilesets/frlg/frlg_outdoor.tres) from
the ripped Tileset 2 sheet.

Run after any change to the tile list. Idempotent — rewrites both files.

Atlas layout (10 cols × 16 rows, 160×256 px):

  Row 0: grass pool × 6 + tall_grass + flower + bush_single + small_tree
  Row 1: grey_boulder + brown_boulder + cliffs × 6 + 2 empty
  Row 2: bush_edges × 3 + big_tree × 3 + 4 road tiles (vertical part 1)
  Row 3: road tiles (vertical part 2) × 4 + rotated roads × 3 + 3 empty
  Rows 4-15: seven 5×3 path groups, two per 3-row band, laid out:
    Rows 4-6:  dirt       | faint_grass
    Rows 7-9:  rocky_dirt | cave
    Rows 10-12: cement    | stone
    Rows 13-15: asphalt   | (empty)
"""

from __future__ import annotations
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets" / "Pokemon Sprites" / "Game Boy Advance - Pokemon FireRed _ LeafGreen - Tilesets - Tileset 2.png"
ATLAS_PNG = REPO / "assets" / "tilesets" / "frlg" / "frlg_outdoor.png"
ATLAS_TRES = REPO / "assets" / "tilesets" / "frlg" / "frlg_outdoor.tres"

BORDER = 1
TILE = 16
STRIDE = 17

# Each path group is identified by the STARTING Tileset 2 row (cols 0-4).
PATH_GROUPS = [
    ("dirt",        0),   # rows 0-2
    ("faint_grass", 3),   # rows 3-5
    ("rocky_dirt",  6),   # rows 6-8
    ("cave",        9),   # rows 9-11
    ("cement",      12),  # rows 12-14
    ("stone",       15),  # rows 15-17
    ("asphalt",     24),  # rows 24-26 (skipping 3 subgroups × 2 rows at 18-23)
]

# Path groups laid out in the atlas two per 3-row band, cols 0-4 and 5-9.
PATH_GROUP_BANDS = [
    ("dirt",        0, 4),  # cols 0-4, rows 4-6
    ("faint_grass", 5, 4),
    ("rocky_dirt",  0, 7),
    ("cave",        5, 7),
    ("cement",      0, 10),
    ("stone",       5, 10),
    ("asphalt",     0, 13),
]
PATH_GROUP_ORIGIN = {name: (atlas_c, atlas_r) for name, atlas_c, atlas_r in PATH_GROUP_BANDS}

# Within a 5×3 path group, the 13 non-null tiles and their local offsets.
# (local_col, local_row) — local_col 0..4, local_row 0..2. Skips (0,1) and (0,2).
PATH_TILE_ROLES = [
    ("middle",       0, 0),
    ("left_edge",    1, 0),
    ("right_edge",   2, 0),
    ("top_edge",     3, 0),
    ("bottom_edge",  4, 0),
    ("bl_corner",    1, 1),
    ("br_corner",    2, 1),
    ("tl_corner",    3, 1),
    ("tr_corner",    4, 1),
    ("int_se",       1, 2),  # interior corner with grass in bottom-right
    ("int_sw",       2, 2),  # grass BL
    ("int_ne",       3, 2),  # grass TR
    ("int_nw",       4, 2),  # grass TL
]

# Standalone tiles (not part of a path group) in atlas coords.
# Format: (atlas_col, atlas_row, source_col, source_row, label, custom_data)
# custom_data is a dict of {"solid": bool, "tall_grass": bool} — only set when true.
STANDALONE = [
    # Row 0 — grass + decor
    (0, 0, 6, 0,   "grass1",       {}),
    (1, 0, 6, 1,   "grass2",       {}),
    (2, 0, 6, 2,   "grass3",       {}),
    (3, 0, 8, 14,  "grass4",       {}),
    (4, 0, 20, 16, "grass5",       {}),
    (5, 0, 24, 16, "grass6",       {}),
    (6, 0, 7, 0,   "tall_grass",   {"tall_grass": True}),  # FIXED: c7r0, not c7r1
    (7, 0, 7, 2,   "flower",       {}),
    (8, 0, 17, 0,  "bush_single",  {"solid": True}),
    (9, 0, 8, 0,   "small_tree",   {"solid": True}),
    # Row 1 — boulders + cliffs + empty
    (0, 1, 8, 18,  "grey_boulder", {"solid": True}),
    (1, 1, 7, 16,  "brown_boulder",{"solid": True}),
    (2, 1, 6, 4,   "cliff_h_L",    {"solid": True}),
    (3, 1, 7, 4,   "cliff_h_M",    {"solid": True}),
    (4, 1, 8, 4,   "cliff_h_R",    {"solid": True}),
    (5, 1, 6, 5,   "cliff_corner", {"solid": True}),
    (6, 1, 7, 5,   "cliff_v",      {"solid": True}),
    (7, 1, 8, 5,   "cliff_v_end",  {"solid": True}),
    # Row 2 — bush edges + big tree + roads
    (0, 2, 6, 22,  "bush_edge_L",  {"solid": True}),
    (1, 2, 7, 22,  "bush_edge_M",  {"solid": True}),
    (2, 2, 8, 22,  "bush_edge_R",  {"solid": True}),
    (3, 2, 17, 13, "tree_tip",     {}),   # passable (goes on Overhead layer)
    (4, 2, 17, 14, "tree_mid",     {"solid": True}),
    (5, 2, 17, 15, "tree_bot",     {"solid": True}),
    (6, 2, 0, 18,  "road_mid_v",   {}),
    (7, 2, 1, 18,  "road_L_top",   {}),
    (8, 2, 2, 18,  "road_R_top",   {}),
    (9, 2, 3, 18,  "road_end",     {}),
    # Row 3 — road v part 2 + rotated
    (0, 3, 1, 19,  "road_L_bot",   {}),
    (1, 3, 2, 19,  "road_R_bot",   {}),
    (2, 3, 3, 19,  "road_corner_SE", {}),
    (3, 3, 4, 19,  "road_corner_NW", {}),
    # (4, 3), (5, 3), (6, 3) filled with rotated road tiles below
]
# Rotated road tiles derived from road_L_top (c1r18) and road_mid_v (c0r18).
# Done at paste time since PIL rotation is lossless for pixel art.
ROTATED_ROADS = [
    (4, 3, 0, 18, "road_mid_h",   -90, {}),  # horizontal interior (symmetric)
    (5, 3, 1, 18, "road_h_top",   -90, {}),  # grass top, road bottom
    (6, 3, 1, 18, "road_h_bot",   +90, {}),  # road top, grass bottom
]


def tile_at(src_img: Image.Image, c: int, r: int) -> Image.Image:
    x = BORDER + c * STRIDE
    y = BORDER + r * STRIDE
    return src_img.crop((x, y, x + TILE, y + TILE))


def build_atlas(src: Image.Image) -> tuple[Image.Image, list[tuple]]:
    atlas_cols = 10
    atlas_rows = 16
    atlas = Image.new("RGBA", (atlas_cols * TILE, atlas_rows * TILE), (0, 0, 0, 0))
    all_tiles = []  # list of (atlas_col, atlas_row, label, custom_data)

    for ac, ar, sc, sr, label, cd in STANDALONE:
        atlas.paste(tile_at(src, sc, sr), (ac * TILE, ar * TILE))
        all_tiles.append((ac, ar, label, cd))
    for ac, ar, sc, sr, label, deg, cd in ROTATED_ROADS:
        t = tile_at(src, sc, sr).rotate(deg, expand=False)
        atlas.paste(t, (ac * TILE, ar * TILE))
        all_tiles.append((ac, ar, label, cd))

    # Path groups.
    for name, src_row_start in PATH_GROUPS:
        atlas_c0, atlas_r0 = PATH_GROUP_ORIGIN[name]
        for role, lc, lr in PATH_TILE_ROLES:
            sc = lc
            sr = src_row_start + lr
            ac = atlas_c0 + lc
            ar = atlas_r0 + lr
            atlas.paste(tile_at(src, sc, sr), (ac * TILE, ar * TILE))
            label = f"{name}_{role}"
            all_tiles.append((ac, ar, label, {}))

    return atlas, all_tiles


def build_tres(all_tiles: list[tuple]) -> str:
    """Generate the TileSet .tres content from the tile list."""
    lines = [
        '[gd_resource type="TileSet" format=3 uid="uid://bpkmnfrlg001"]',
        "",
        '[ext_resource type="Texture2D" path="res://assets/tilesets/frlg/frlg_outdoor.png" id="1_tex"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="frlg_outdoor"]',
        'texture = ExtResource("1_tex")',
        'texture_region_size = Vector2i(16, 16)',
        "; Auto-generated by tools/build_frlg_atlas.py — do not hand-edit.",
    ]
    # Sort by (row, col) for a predictable .tres diff.
    for ac, ar, label, cd in sorted(all_tiles, key=lambda t: (t[1], t[0])):
        lines.append(f"; {label}")
        lines.append(f"{ac}:{ar}/0 = 0")
        if cd.get("solid"):
            lines.append(f"{ac}:{ar}/0/custom_data_0 = true")
        if cd.get("tall_grass"):
            lines.append(f"{ac}:{ar}/0/custom_data_1 = true")

    lines.extend([
        "",
        "[resource]",
        "tile_size = Vector2i(16, 16)",
        'custom_data_layer_0/name = "solid"',
        "custom_data_layer_0/type = 1",
        'custom_data_layer_1/name = "tall_grass"',
        "custom_data_layer_1/type = 1",
        'sources/0 = SubResource("frlg_outdoor")',
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    src = Image.open(SRC).convert("RGBA")
    atlas, all_tiles = build_atlas(src)
    ATLAS_PNG.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(ATLAS_PNG)
    ATLAS_TRES.write_text(build_tres(all_tiles))
    print(f"Atlas:   {ATLAS_PNG.relative_to(REPO)} ({atlas.size[0]}×{atlas.size[1]}, {len(all_tiles)} tiles)")
    print(f"TileSet: {ATLAS_TRES.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
