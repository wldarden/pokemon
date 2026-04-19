# Pokemon (Gen 1, 151 only) — Phase 1 Design

**Date:** 2026-04-18
**Status:** Approved, ready for implementation planning
**Scope:** Phase 1 of a personal-use Pokemon clone — overworld movement, wild battle, trainer battle

## Goal

Build a personal Pokemon-style game featuring only the original 151 Pokemon, with Gen 3 FireRed/LeafGreen-era visuals and mechanics. Phase 1 delivers the three pillars that together account for the majority of the game's core mechanics: running around a map, fighting a wild Pokemon, and fighting a trainer.

This is a personal project — not for distribution. Ripped FR/LG sprites are acceptable as source assets.

## Stack

- **Engine:** Godot 4 (GDScript)
- **Rendering:** 240×160 native render resolution, nearest-neighbor upscaled to window (typically 960×640 at 4×). Pixel-perfect GBA look.
- **Tile size:** 16×16
- **Level editor:** Godot's built-in TileMap editor
- **Testing:** GUT (Godot Unit Testing) for pure functions (`DamageCalc`, stat calculation); manual playtest per milestone for scene-level behavior

### Why Godot

A tilemap-heavy 2D RPG with scene transitions, dialog, sprite animation, and menus is the canonical Godot project. Built-in tilemap editor alone saves substantial work vs. a code-only framework. Scene system maps naturally to Overworld / Battle / Menu separation. GDScript is fast to write and iterate in.

## Visual target

- Reference: Pokemon FireRed / LeafGreen (GBA, 2004) — the Gen 1 remakes that ran on the Emerald/Sapphire engine.
- 240×160 base resolution (actual GBA resolution)
- 16×16 tile grid
- Ripped sprite sheets from The Spriters Resource / PokéCommunity as source art (user sources these outside of Claude)
- Integer scaling only — no fractional upscale, no filtering

## Phase 1 scope

### Phase 1.1 — Overworld demo

- Single test scene, approximately 20×15 tiles
- Tileset: path, grass, tall grass, tree, fence (~6 tile types)
- Player: 4-direction grid-based movement, one tile per input, tweened smoothly (~0.15s per step), input locked during tween
- Walk animation per direction
- Camera2D follows player
- Solid tiles (tree, fence) block movement via collision check before tween starts

**Not in Phase 1.1:** NPCs, signs, dialog boxes, HUD, map-to-map transitions

### Phase 1.2 — Wild battle

- `EncounterZone` node covers tall grass tiles; holds a species/level pool
- On every player step inside the zone, rolls a random chance (default 1/10) to trigger encounter
- Hard cut transition to Battle scene (no flash transition yet)
- Battle scene renders: player back sprite, wild front sprite, two HP bar HUDs, move menu, dialog line
- One Pokemon vs. one Pokemon, each with 4 moves
- Turn order by Speed stat
- Damage calculation uses **real FireRed/LeafGreen formulas from day one** — no stubs
- Fainting ends the battle, XP notification (text only), return to overworld, player position preserved

**Not in Phase 1.2:** catching, running, switching, status effects, PP depletion, items

### Phase 1.3 — Trainer battle

- `Trainer` NPC placed on the path
- Line-of-sight: configurable number of tiles in facing direction
- Player entering sightline triggers: "!" sprite above trainer → trainer walks to stop one tile from player → dialog ("I challenge you!") → battle
- Reuses Battle scene; `context.is_trainer = true` is carried in the payload (will later gate disabling run/catch and awarding prize money — not yet implemented in Phase 1, since those features don't exist yet)
- On win: trainer's id added to `GameState.defeated_trainers`; trainer no longer triggers battles
- Trainer has one Pokemon in Phase 1

**Not in Phase 1.3:** branching dialog, prize money, multi-Pokemon trainer teams

### Deferred to Phase 2+

Party of 6, switching, catching, items/bag, Pokédex UI, leveling up, evolution, map-to-map transitions, full dialog system, save/load, audio.

## Project layout

```
pokemon-gameboy/
├── project.godot
├── assets/
│   ├── sprites/
│   │   ├── pokemon/              # front_001.png, back_001.png, ... indexed by Dex #
│   │   ├── trainers/
│   │   ├── player/
│   │   └── ui/
│   ├── tilesets/
│   │   └── outdoor.png
│   ├── fonts/
│   └── audio/                    # empty in Phase 1
├── data/                         # Godot Resources (.tres) — the "database"
│   ├── species/                  # 001_bulbasaur.tres, ...
│   ├── moves/                    # tackle.tres, ember.tres, ...
│   └── type_chart.tres
├── scenes/
│   ├── overworld/
│   │   ├── Overworld.tscn
│   │   ├── Player.tscn
│   │   ├── Trainer.tscn
│   │   └── EncounterZone.tscn
│   ├── battle/
│   │   ├── Battle.tscn
│   │   ├── BattleUI.tscn
│   │   └── BattleHUD.tscn
│   └── ui/
│       └── DialogBox.tscn
├── scripts/
│   ├── overworld/                # player.gd, trainer.gd, encounter_zone.gd
│   ├── battle/                   # battle_state.gd, damage_calc.gd, turn_resolver.gd
│   ├── data/                     # species_resource.gd, move_resource.gd, pokemon_instance.gd
│   └── globals/                  # game_state.gd (autoload)
├── tests/                        # GUT tests
│   └── unit/                     # test_damage_calc.gd, test_stats.gd
├── docs/
│   └── superpowers/specs/
└── .gitignore
```

### Conventions

- **Godot Resources for static data, not JSON.** Each species is a `.tres` with typed fields. Godot's inspector becomes a Pokédex editor.
- **`PokemonInstance` is a runtime GDScript class, not a Resource** — it holds mutating state (HP, XP, status). Species resources are immutable templates.
- **`GameState` autoload singleton** holds player party, position for battle return, defeated trainers, Pokédex flags — anything that persists across scene transitions.
- **Battle is its own scene**, instantiated on top of Overworld by a controller, freed after `battle_ended` signal.

## Data model

### `Species` (Resource, one `.tres` per species, 151 total)

```gdscript
class_name Species extends Resource
@export var dex_number: int            # 1–151
@export var name: String               # "Bulbasaur"
@export var types: Array[Type]         # [GRASS, POISON]
@export var base_stats: Dictionary     # {hp:45, atk:49, def:49, spa:65, spd:65, spe:45}
@export var catch_rate: int
@export var base_exp_yield: int
@export var growth_rate: GrowthRate    # FAST, MEDIUM_FAST, SLOW, ...
@export var learnset: Array[LearnsetEntry]   # {level, move}
@export var evolutions: Array[Evolution]     # {method, param, into_species}
@export var front_sprite: Texture2D
@export var back_sprite: Texture2D
@export var abilities: Array[Ability]  # Phase 2+
```

### `Move` (Resource, one `.tres` per move)

```gdscript
class_name Move extends Resource
@export var name: String
@export var type: Type
@export var category: Category         # PHYSICAL, SPECIAL, STATUS
@export var power: int
@export var accuracy: int
@export var pp: int
@export var priority: int
@export var effect: MoveEffect         # resource describing status/stat-change/etc.
```

### `TypeChart` (one Resource)

Stored as `Dictionary[Type, Dictionary[Type, float]]` — value is 0.0 (immune), 0.5 (resist), 1.0 (neutral), or 2.0 (super effective). Phase 1 populates the subset of 15 Gen 1 types actually exercised by the Phase 1 move set; all Gen 1 types will be filled in during data-population work.

### `PokemonInstance` (runtime class, not Resource)

```gdscript
class_name PokemonInstance
var species: Species
var nickname: String
var level: int
var experience: int
var ivs: Dictionary                    # {hp:0-31, atk, def, spa, spd, spe}
var evs: Dictionary                    # {hp:0-252, ...}
var nature: Nature
var ability: Ability
var moves: Array[MoveSlot]             # max 4, each has move + pp_current
var current_hp: int
var status: StatusCondition
var held_item: Item                    # null in Phase 1

func max_hp() -> int                   # FR/LG formula
func stat(stat: StatKey) -> int        # base + IV + EV + nature + level
```

### `DamageCalc` (pure function)

`DamageCalc.calculate(attacker: PokemonInstance, defender: PokemonInstance, move: Move, context: BattleContext) -> DamageResult`

- No side effects. Returns damage amount + flags (crit, effectiveness, miss).
- Pure function → unit-testable with GUT without instantiating scenes.
- Implements the FR/LG damage formula: level factor, attack/defense ratio, STAB, type effectiveness, crit, random roll 85–100%.

### Design rationale

- **Species-as-resource** means adding a new Pokemon later = drop a new `.tres` file. No code change.
- **PokemonInstance-as-class** (not resource) because it mutates constantly; serialization for save games uses `var_to_str` on a dict representation.
- **Full FR/LG ruleset data shape from day one** (IVs, EVs, nature, split Sp.Atk/Sp.Def, held items) — Phase 1 leaves some fields at defaults. No schema rewrite in Phase 2.

## Scene architecture & state flow

### `GameState` autoload singleton

```gdscript
extends Node  # autoloaded as /root/GameState
var player_party: Array[PokemonInstance]
var player_position: Vector2i
var player_facing: Direction
var defeated_trainers: Dictionary      # {trainer_id: true}
var pokedex_seen: Dictionary
var pokedex_caught: Dictionary
```

### Overworld scene

- `Player` node: input → tile movement → emits `moved(position)` signal
- `EncounterZone` nodes listen for player moves inside their area, roll encounter chance, emit `wild_encounter(species, level)`
- `Trainer` nodes check sightline against player on every move, emit `trainer_spotted(trainer_id)`
- A scene controller (parent of the overworld scene) receives these signals and launches Battle

### Battle scene

```gdscript
# Battle.tscn root
func start(player_party: Array, enemy_party: Array, context: BattleContext) -> void
signal battle_ended(result: BattleResult)
```

Internal state machine: `IntroAnim → ChooseAction → ResolveTurn → CheckFaint → Outcome`. `BattleResult` carries winner, XP gained, money, caught flag.

### Transition flow

```
Overworld                  BattleSceneController              Battle
   │                              │                              │
   │ wild_encounter signal ──────▶│                              │
   │                              │ hide_overworld()             │
   │                              │ add_child(Battle.tscn)       │
   │                              │ battle.start(party, wild)    │
   │                              │─────────────────────────────▶│
   │                              │                              │ ... turn loop ...
   │                              │ battle_ended(result) ◀───────│
   │                              │ apply_result_to_party()      │
   │                              │ queue_free(battle)           │
   │                              │ show_overworld()             │
   │ (player position restored)   │                              │
```

### Why this shape

- Pure data on `GameState`. Both scenes read/write the same `PokemonInstance` objects. No sync issues.
- Battle doesn't depend on Overworld types (and vice versa). Coupled only through shared `PokemonInstance` objects and the `battle_ended` signal. Each scene is testable in isolation.
- Trainer battle reuses the Battle scene verbatim — only the context payload differs.

## Phase 1 build order

Each step ends at a demonstrable checkpoint.

1. **Project skeleton**
   - Godot project created, render resolution 240×160, window 960×640 (4× integer scale), stretch_mode=viewport, stretch_aspect=keep
   - Folder structure per "Project layout" above
   - `.gitignore` covering `.godot/`, `.import/`, `.superpowers/`
   - **Checkpoint:** blank window runs, pixel-perfect scaling confirmed with a test rectangle

2. **Tilemap test scene**
   - Import tileset PNG, define tiles in TileSet resource
   - Paint ~20×15 map in TileMap editor
   - **Checkpoint:** static map renders at native resolution, upscales cleanly

3. **Player movement**
   - `Player.tscn`: AnimatedSprite2D + grid mover script
   - Grid-based tween, ~0.15s per tile, input locked during tween
   - 4-direction walk animations (idle + walking)
   - Camera2D child follows player
   - Solid tile collision check before committing to a move
   - **Checkpoint:** walk around the map, cannot clip through trees/fences

4. **Data model scaffolding**
   - Implement `Species`, `Move`, `Type` enum, `TypeChart`, `PokemonInstance`, `MoveSlot`, `DamageCalc`, `MoveEffect`, supporting enums (Nature, StatusCondition, Category, etc.)
   - Define 3 species resources (one of each starter, or user's choice — covering Grass/Fire/Water typing)
   - Define 4 move resources: Tackle, Scratch, Vine Whip, Ember
   - Populate type chart for the handful of types involved in Phase 1 data
   - GUT test: construct two `PokemonInstance`s at known levels, assert `DamageCalc.calculate` returns a value matching a reference calculator (e.g., Bulbapedia's damage formula page) within the random roll range
   - **Checkpoint:** unit tests pass for damage formula

5. **Battle scene**
   - `Battle.tscn`: background, player back sprite, enemy front sprite, two HP bar HUDs, move menu (4 buttons), dialog line
   - Battle state machine: `Intro → ChooseMove → ResolveTurn → CheckFaint → Outcome`
   - Turn resolution: sort by Speed, apply `DamageCalc`, tween HP bars, check faint
   - Text printer: one character per frame tick, press confirm to advance
   - `battle_ended` signal returns `BattleResult`
   - **Checkpoint:** standalone `BattleTest.tscn` launches battle with two hardcoded `PokemonInstance` objects; fight one until faint

6. **Wild encounter trigger**
   - `EncounterZone` node with species/level pool property
   - Listens for player `moved` signal, rolls encounter chance, picks from pool
   - `BattleSceneController` loads and unloads Battle.tscn
   - Player position preserved across battle
   - **Checkpoint:** walking in tall grass eventually triggers battle; return to overworld works

7. **Trainer battle**
   - `Trainer.tscn`: sprite + `sight_tiles` int + `facing` direction
   - Sight cone computed as set of tile positions ahead of trainer in their facing direction
   - Check sightline whenever player `moved` fires
   - On spot: "!" sprite tween, trainer walks to one tile from player, dialog line, battle
   - Same Battle scene, `context.is_trainer = true` carried in payload (reserved for Phase 2 run/catch/prize-money gating)
   - Win → add trainer id to `GameState.defeated_trainers` → trainer no longer checks sightline
   - **Checkpoint:** walk into trainer sightline → battle → defeat → can walk past freely

### Testing approach

- GUT unit tests for pure logic: `DamageCalc`, stat calculations, XP curves, type effectiveness lookups
- Manual playtest at each milestone checkpoint above
- Phase 1 is scaffolding — don't over-test. Heavier test investment lands in Phase 2 once mechanics stabilize.

## Phase 2+ roadmap (sketch)

Not committing to order — scoping so Phase 1 decisions don't paint into corners.

- **Phase 2 — Party & progression:** party of 6, switching, EXP gain, leveling up, move learning, evolution, Pokémon Center heal. Full FR/LG battle math (STAB, crits, multi-hit, status effects).
- **Phase 3 — Catching & inventory:** Poké Balls, catch formula, bag, item use in battle, running, money, Poké Mart.
- **Phase 4 — Dialog & NPCs:** proper dialog system (branching, portraits optional), signs, general NPCs, starter-choice flow.
- **Phase 5 — Multi-map world:** map-to-map transitions, warp points, Kanto routes, save/load.
- **Phase 6 — Polish:** audio, battle animations, screen transitions (FR/LG flash), Pokédex UI, menus, settings.
- **Phase 7 — Personal twists:** user's mechanical divergences from FR/LG.

### What Phase 1 makes easy later

- Adding a new Pokemon = new `.tres` file. No code change.
- Adding a new move effect = extend `MoveEffect` resource; battle state machine resolves effects generically.
- Adding a new map = new scene using the same Player/Trainer/EncounterZone components.
- Save/load = serialize `GameState`.

### What needs revisiting

- Battle state machine grows to cover switching, items, catching — design for extensibility but don't over-engineer in Phase 1.
- Dialog system gets real design in Phase 4. Phase 1 dialog is a single-line shim.

## Open questions

None at time of approval. User agreed to all sections.

## Legal / asset note

Ripped FR/LG sprites are used for personal reference only. Project is not for distribution. If distribution is ever desired, all copyrighted assets must be replaced with original or CC-licensed art before release.
