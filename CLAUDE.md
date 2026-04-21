# Pokemon Gameboy (Gen 1, 151 only)

A personal 2D top-down Pokemon clone in Godot, restricted to the original 151 Pokemon, built with FireRed/LeafGreen-era visuals and mechanics. Not for distribution — asset licensing is personal-use only.

**Design spec:** [`docs/superpowers/specs/2026-04-18-pokemon-phase-1-design.md`](docs/superpowers/specs/2026-04-18-pokemon-phase-1-design.md) is the source of truth for Phase 1 scope, data model, and architecture. Read it before making architectural changes.

## Stack

- **Engine:** Godot 4 (GDScript)
- **Rendering:** 240×160 native, nearest-neighbor upscaled to 960×640 window (4× integer scale). Pixel-perfect GBA look — no filtering, no fractional scaling.
- **Tile size:** 16×16
- **Testing:** GUT (Godot Unit Testing) for pure functions (`DamageCalc`, stat calc). Manual playtest for scene-level behavior.

## Build & Run

```bash
# Open in Godot editor
godot -e .

# Run the main scene from CLI
godot .

# Run GUT tests (once GUT is set up)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests
```

## Project Layout

```
assets/      # sprites, tilesets, fonts, audio
data/        # .tres Resource files — species/, moves/, type_chart.tres
scenes/      # .tscn files — overworld/, battle/, ui/
scripts/     # .gd files — overworld/, battle/, data/, globals/
tests/       # GUT tests
docs/        # design docs, including the Phase 1 spec
```

## Core Conventions

- **Godot Resources for static data, not JSON.** Each Pokemon species is a `.tres` file. Same for moves, type chart. The Godot inspector becomes a Pokédex editor.
- **`PokemonInstance` is a plain GDScript class**, not a Resource. It holds mutating runtime state (HP, XP, status). Species resources are immutable templates.
- **`GameState` autoload singleton** (`scripts/globals/game_state.gd`) holds all persistent cross-scene state: player party, position, defeated trainers, Pokédex flags.
- **Battle is its own scene.** A `BattleSceneController` instantiates `Battle.tscn` on top of Overworld, awaits the `battle_ended` signal, frees the battle scene. Battle doesn't know about Overworld or vice versa.
- **`DamageCalc` is a pure function.** No side effects, returns a `DamageResult`. Unit-testable without instantiating scenes.
- **Full FR/LG data shape from day one.** Species have IVs, EVs, natures, abilities, held items in their schema even though Phase 1 leaves some unused. Avoids Phase 2 schema rewrites.

## Architectural Preferences

- **Flat class hierarchies.** Don't add intermediate base classes unless they carry substantial shared behavior.
- **Local over global.** Behavior lives on the object that does it (player's `moved` signal fires from Player, not from a global manager polling Player's position).
- **Dictionaries over fixed arrays** for evolving key sets — safer during development.
- **Verify all call sites when fixing a pattern bug.** If you change how one thing works, grep the whole codebase; don't fix one site and leave others stale.

## Phase 1 Scope (from design doc)

1. **Overworld demo** — ~20×15 tile test map, grid-based player movement, solid-tile collision.
2. **Wild battle** — tall-grass encounter trigger, full FR/LG damage formula (no stubs), turn order by Speed, HP bars, move menu.
3. **Trainer battle** — sightline detection, "!" + walk-up, reuses Battle scene.

**Deferred to Phase 2+:** party of 6, switching, catching, items, Pokédex UI, leveling up, evolution, multi-map transitions, full dialog system, save/load, audio.

## Asset Reference

- **FR/LG tileset layout:** [`docs/frlg_tileset_reference.md`](docs/frlg_tileset_reference.md) — Spriters Resource conventions (17-px stride, 1-px border), the 5×3 path-group autotile structure, locations of all our extracted tiles, and how to extend the atlas.
- **Atlas build tool:** [`tools/build_frlg_atlas.py`](tools/build_frlg_atlas.py) — regenerates `assets/tilesets/frlg/frlg_outdoor.png` and `.tres` from the source rips. Idempotent — rerun after any change.
- **Source rips:** `assets/Pokemon Sprites/` is gitignored (ripped FR/LG, personal-use only).

## Legal / Asset Note

Ripped FR/LG sprites are used as source assets for personal reference only. This project is not distributable in its current form. If distribution is ever desired, all copyrighted assets must be replaced with original or CC-licensed art first.
