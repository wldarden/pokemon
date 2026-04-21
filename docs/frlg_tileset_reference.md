# FR/LG Tileset Reference

Reference notes on the ripped FR/LG source tilesheets and our extraction layout. The source PNGs live under `assets/Pokemon Sprites/` and are **gitignored** (personal reference only, not distributable).

**Build tool:** [`tools/build_frlg_atlas.py`](../tools/build_frlg_atlas.py) — run it to regenerate `assets/tilesets/frlg/frlg_outdoor.png` and `.tres` from the source rips. Edit the constants at the top of the script to add new tile groups.

## Source file conventions (The Spriters Resource rips)

All the FR/LG tileset rips follow the same layout convention:

- Each tile is **16×16 px**.
- **1-pixel transparent gap between tiles.**
- **1-pixel transparent border** around the whole image.
- Background (fuchsia / magenta) indicates transparency.
- Tile at column `c`, row `r` is at pixel `(1 + c*17, 1 + r*17)` through `(1 + c*17 + 16, 1 + r*17 + 16)`. Stride is 17 px, not 16.

Tileset 2 (`Tilesets - Tileset 2.png`, 477×800 px) = **28 cols × 47 rows**. This is the main outdoor terrain sheet — grass, paths, cliffs, water, trees, buildings, fences, rocks.

**Note:** Other sheets (especially the generic `Tileset.png`) do NOT have globally aligned subgroups — each subgroup starts at its own offset. Only Tileset 2 has a clean universal 17-px stride.

## Path autotile convention (5×3 per group)

Tileset 2 has **multiple path-type subgroups**, each occupying a 5-column × 3-row block. The column offset is 0-4, and each group starts at a different row. Within a group the 15 tile positions are:

```
Row 0 (edges)    : [middle] [left_edge] [right_edge] [top_edge] [bottom_edge]
Row 1 (outer)    : [ null ] [bl_corner] [br_corner] [tl_corner] [tr_corner]
Row 2 (interior) : [ null ] [int_grass_SE] [int_grass_SW] [int_grass_NE] [int_grass_NW]
```

13 usable tiles; the two "null" slots at `(c0, r1)` and `(c0, r2)` of each group are duplicates of `middle`.

- **middle**: fully path, no grass on any side. Used for path interiors (the all-dirt area).
- **edges** (left/right/top/bottom): grass on that ONE side, path elsewhere. Used where a rectangular path region meets open grass along one edge.
- **outer corners** (tl/tr/bl/br): grass in that CORNER QUADRANT of the tile. Used at the 4 convex corners of a rectangular path.
- **interior corners** (int_NE/NW/SE/SW): a small patch of grass JUTTING INTO the path from that corner. Used when a path wraps around a concave grass corner (e.g., around an interior hollow or an L-shaped turn).

This gives a full 13-tile autotile — enough to paint any rectangular path with holes / L-turns cleanly.

## Path subgroups we extracted

Each subgroup's top-left source cell is at `(c0, source_row)`:

| # | Name         | Source row range | Atlas position |
|---|--------------|------------------|----------------|
| 1 | dirt         | rows 0–2         | atlas (0, 4)   |
| 2 | faint_grass  | rows 3–5         | atlas (5, 4)   |
| 3 | rocky_dirt   | rows 6–8         | atlas (0, 7)   |
| 4 | cave         | rows 9–11        | atlas (5, 7)   |
| 5 | cement       | rows 12–14       | atlas (0, 10)  |
| 6 | stone        | rows 15–17       | atlas (5, 10)  |
|   | *(skipped)*  | rows 18–23       | 3 × 2-row subgroups, not path autotiles |
| 8 | asphalt      | rows 24–26       | atlas (0, 13)  |
| 9 | *(beach)*    | rows 27–29       | skipped — no water yet |

## Other notable Tileset 2 tiles

| Source coord | Tile                | Atlas position |
|--------------|---------------------|----------------|
| (c6, r0)     | plain grass #1      | atlas (0, 0)   |
| (c6, r1)     | plain grass #2      | atlas (1, 0)   |
| (c6, r2)     | plain grass #3      | atlas (2, 0)   |
| (c7, r0)     | **tall grass** (encounter) | atlas (6, 0) |
| (c7, r2)     | flower              | atlas (7, 0)   |
| (c8, r0)     | small cuttable tree | atlas (9, 0)   |
| (c8, r14)    | plain grass #4      | atlas (3, 0)   |
| (c17, r0)    | small bush (1-tile) | atlas (8, 0)   |
| (c17, r13)   | big tree tip        | atlas (3, 2)   |
| (c17, r14)   | big tree mid        | atlas (4, 2)   |
| (c17, r15)   | big tree bottom     | atlas (5, 2)   |
| (c20, r16)   | plain grass #5      | atlas (4, 0)   |
| (c24, r16)   | plain grass #6      | atlas (5, 0)   |
| (c6–8, r4)   | horizontal cliff (L/M/R) | atlas (2–4, 1) |
| (c6–8, r5)   | cliff corner + vertical cliff | atlas (5–7, 1) |
| (c6–8, r22)  | bush edges (L/M/R horizontal) | atlas (0–2, 2) |
| (c0, r18)    | plain road (vertical orientation) | atlas (6, 2); also rotated 90° at atlas (4, 3) |
| (c1–4, r18–19)| road edges, corners (vertical by default) | atlas (7–9, 2) and (0–3, 3) |
| (c8, r18)    | grey boulder        | atlas (0, 1)   |
| (c7, r16)    | brown boulder       | atlas (1, 1)   |

## Extracted atlas layout (assets/tilesets/frlg/frlg_outdoor.png)

The build tool packs everything into a **10 cols × 16 rows** atlas (160×256 px). Layout:

```
Row  0:   6 grass | tall_grass | flower | bush_single | small_tree
Row  1:   grey_boulder | brown_boulder | 6 cliff tiles
Row  2:   3 bush_edges | 3 big_tree | road_mid_v | road_L/R_top | road_end
Row  3:   road_L/R_bot | road_corner_SE/NW | road_mid_h | road_h_top | road_h_bot
Rows 4-6:  dirt path group       | faint_grass path group
Rows 7-9:  rocky_dirt path group | cave path group
Rows 10-12: cement path group    | stone path group
Rows 13-15: asphalt path group   | (empty)
```

Each path group occupies `cols (0-4)` or `cols (5-9)` within a 3-row band, with the same internal 5×3 offset layout documented above.

## Extending

To add a new tile:

1. Identify its source coord in Tileset 2 (or another source sheet if it's 16×16 and 17-strided — otherwise update `build_frlg_atlas.py` to handle the other sheet's coordinate system).
2. Append to the `STANDALONE` list (for one-off tiles) or `PATH_GROUPS` (for a full 5×3 autotile block) in `tools/build_frlg_atlas.py`.
3. Re-run `python3 tools/build_frlg_atlas.py`. It rewrites both the atlas PNG and the TileSet .tres.
4. In `scripts/overworld/overworld_bootstrap.gd`, add a constant for the new atlas coord (standalone) or a new `const FOO_PATH := { ... }` block (path group) matching the atlas positions the script printed.

## Other FR/LG rip files (not yet extracted)

Under `assets/Pokemon Sprites/` (local-only):

- **Tileset 1.png** — city/building exteriors (Poké Mart, Pokémon Center, gyms, etc.).
- **Tileset.png** — misc outdoor props (berries, mushrooms, smaller items). Subgroups are NOT globally 17-strided — each subgroup has its own offset.
- **Animated Tiles.png** — sea, fast-current water, flower animations.
- **Buildings.png** — duplicate/alternate building set.
- **Maps/*.png** — pre-composed route/town maps (not tiles themselves — useful as references).
- **Battle Effects/*.png** — battle HUD, attack effect frames, Poké Ball animations (for Phase 5+).
