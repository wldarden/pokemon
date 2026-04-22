# Phase 2d — Pokémon Centers + Starter selection

**Date:** 2026-04-21
**Status:** Approved, ready for implementation planning
**Scope:** Fourth sub-phase of Phase 2. Replaces the 2c debug-seeded party and the `H` debug-heal key with the two features they stood in for: a first-boot starter-selection screen that populates `player_party`, and an in-world Pokémon Center where the player enters the building, talks to a nurse, and watches the party get fully healed. Establishes the overworld dialog system, scene-transition system, and generic NPC interaction pattern along the way.

## Goal

When the player boots the game and `player_party` is empty, they pick one of three starters from a simple modal and enter the overworld with that Pokémon in slot 0. When they walk onto the door tile of a Pokémon Center building on the overworld map, the screen fades, a new `PokemonCenter.tscn` scene loads showing the canonical FR/LG PC interior, and the player can face the nurse and press A to heal the party. Stepping back onto the exit mat fades back to the overworld one tile below the door. The H debug-heal key stays as a dev shortcut.

## Scope

### In

- **Overworld dialog system** — `scenes/ui/DialogBox.tscn` + `scripts/ui/dialog_box.gd`, an autoload CanvasLayer with a bottom-anchored 240×40 panel, typewriter effect (same `CHAR_PRINT_DELAY = 0.03` as the battle dialog), ui_accept to advance. API: `queue(lines: Array[String]) -> Signal` that fires when the last line is dismissed. Awaits the current sequence if already open.
- **Dialog sequence builder** — `scripts/overworld/dialog_sequence.gd`, `class_name DialogSequence extends RefCounted` with chainable `.say(text)`, `.wait(seconds)`, `.call_fn(callable)`, `.run() -> await`. Used by nurse + starter narration.
- **Scene-transition system** — `SceneFade` autoload (CanvasLayer at layer 100 with a black ColorRect). `fade_out(duration=0.25) -> await`, `fade_in(duration=0.25) -> await`. Persistent across scene swaps; the black fill stays visible through the swap.
- **`GameState` additions:**
  - `next_spawn: Dictionary` (keys: `scene: PackedScene`, `cell: Vector2i`, `facing: int`) — set by the caller before `change_scene_to_packed`; consumed and cleared by the receiving scene's `_ready()`.
  - `heal_party() -> void` — iterate party, set `current_hp = max_hp()`, clear `status`, restore `MoveSlot.pp` to `max_pp`. Idempotent; no-op on empty party.
  - Drop `_debug_seed_party()` and its `_ready()` call.
- **Starter-pick modal** — `scenes/ui/StarterSelect.tscn` + `scripts/ui/starter_select.gd`. Three Poké Ball slots side-by-side (Bulbasaur / Charmander / Squirtle), arrow-nav, A confirm (no cancel — can't back out of first boot). Emits `starter_chosen(dex_number: int)`. Overworld instantiates it when `player_party.is_empty()` at `_ready()`.
- **Generic NPC interaction pattern** — blockers-group nodes with an `on_interact()` method become "talkable." Extension to `Player._unhandled_input`: on A press, compute the one-tile-ahead cell from `facing`, find any blocker at that cell, call `on_interact()` if the method exists.
- **Generic door/trigger pattern** — separate `doors` group. On `Player._tween_to` completion, if the target cell matches a `doors`-group node with an `on_enter(player)` method, call it. Used by PC entrance (Overworld side) and exit mat (interior side).
- **`scripts/overworld/door.gd`** — `class_name Door extends Area2D`. Exports: `target_scene: PackedScene`, `target_cell: Vector2i`, `target_facing: int`. `on_enter(player)` sets `GameState.next_spawn` and fires the fade + scene change.
- **Pokémon Center exterior on `Overworld.tscn`** — 4×4 tiles extracted from `assets/Pokemon Sprites/.../Buildings.png` into a small static sprite (single PNG, no tileset). Placed at a chosen cell (target: around (10, 4) near the top of the existing path — final cell picked during implementation). Collision: a child `StaticBody2D` with one rectangle covering the 3×4 non-door area (decided up-front — avoids TileMap round-trips during iteration).
- **`PokemonCenter.tscn` interior scene** — viewport-sized `TextureRect` with a pre-cropped PC interior image (from `assets/Pokemon Sprites/.../Pokemon Center _ Mart.png`). Player node as a child (same `scenes/overworld/Player.tscn`). `Nurse` invisible hitbox behind the counter (group `blockers`, method `on_interact`). `ExitMat` Area2D at the entry tile (group `doors`). Camera2D with bounds fit to the interior dimensions.
- **Nurse heal script** — `scripts/overworld/nurse.gd` attached to the Nurse node. `on_interact()` runs a three-line DialogSequence with a 0.3s pause and `GameState.heal_party()` call in the middle:
  - "Welcome to the POKéMON CENTER!"
  - "We restore your POKéMON to full health."
  - (wait 0.3s + `heal_party()`)
  - "…Done! We hope to see you again!"
- **Building / map asset tooling** — `tools/build_buildings_atlas.py`. Extracts the PC exterior tiles from the Buildings sheet into `assets/buildings/frlg/pc_exterior.png` (+ a minimal `.tres` TileSet or direct-sprite depending on the integration pick). Crops the PC interior from the Maps sheet into `assets/maps/frlg/pc_interior.png` as a single background image. Records coordinates for Mart, Gym, etc. in comments for future phases.
- **`Overworld.tscn` wiring** — new `PokemonCenter` holder node (4×4 sprite + collision + `Door` child). Door exports point to `PokemonCenter.tscn`, target cell = exit-mat cell inside the interior, target facing = UP.
- **Autoload registration** — `SceneFade` and `DialogBox` registered in `project.godot` alongside `GameState`.
- **Unit tests** — `tests/unit/test_heal_and_spawn.gd` covering `heal_party()`, `DialogSequence` builder state, and `Player.apply_spawn()`. Target: 6 new tests, suite 50 → 56.

### Out (deferred)

- **Oak cutscene / Oak's Lab interior scene** for starter selection — Phase 3+.
- **Mart / shopping flow** — Phase 3+ (BAG doesn't exist yet).
- **Audio** (fanfare, footsteps, dialog beeps, healing chime) — Phase 3+.
- **Save/load** — Phase 5+. First-boot check is `GameState.player_party.is_empty()` in memory only.
- **PC-box computer corner** for storing overflow Pokémon — Phase 3+ when party size can exceed 6.
- **Additional towns / multi-map overworld** — future phase (infrastructure from `next_spawn` + `SceneFade` generalizes).
- **Gym buildings / Elite Four** — future phases.
- **Dialog portrait sprites** — future polish pass.
- **Nurse's Pokéball-pulse animation + chime** during heal — Phase 3+ (tied to audio).
- **"Your Pokémon are already healthy"** short-circuit message — matches FR/LG, which always runs the full sequence regardless.

## Architecture

Matches the project's flat-hierarchy preference: autoload singletons for session-wide UI (DialogBox, SceneFade), scene-local scripts for building interiors, pure-function helpers for testable logic.

### New files

**`scenes/ui/DialogBox.tscn` + `scripts/ui/dialog_box.gd`**

```gdscript
class_name DialogBox
extends CanvasLayer
## Autoload singleton. Call DialogBox.queue(lines) from anywhere.

signal closed

func queue(lines: Array[String]) -> Signal:
    # If currently open, awaits the current sequence, then starts this one.
    # Returns `closed` signal that emits when the last line is dismissed.
    ...

func is_open() -> bool

func _input(event):
    # Consumes ui_accept when open (typewriter skip + line advance).
    # Sets player.input_locked via group lookup.
```

**`scripts/overworld/dialog_sequence.gd`**

```gdscript
class_name DialogSequence
extends RefCounted

var _steps: Array = []   # [{"kind": "say", "text": "..."}, {"kind": "wait", "seconds": 0.3}, ...]

func say(text: String) -> DialogSequence:
    _steps.append({"kind": "say", "text": text})
    return self

func wait(seconds: float) -> DialogSequence:
    _steps.append({"kind": "wait", "seconds": seconds})
    return self

func call_fn(callable: Callable) -> DialogSequence:
    _steps.append({"kind": "call", "fn": callable})
    return self

func run() -> void:
    # Iterates _steps sequentially, awaiting DialogBox.queue() for say lines,
    # create_timer for waits, and calling callables synchronously.
    ...

func size() -> int:
    return _steps.size()
```

**`scenes/ui/SceneFade.tscn` + `scripts/ui/scene_fade.gd`**

```gdscript
extends CanvasLayer
## Autoload singleton. Layer = 100 so it overlays everything.

@onready var rect: ColorRect = $Rect

func fade_out(duration: float = 0.25) -> void:
    var tw := create_tween()
    tw.tween_property(rect, "modulate:a", 1.0, duration)
    await tw.finished

func fade_in(duration: float = 0.25) -> void:
    var tw := create_tween()
    tw.tween_property(rect, "modulate:a", 0.0, duration)
    await tw.finished
```

**`scenes/ui/StarterSelect.tscn` + `scripts/ui/starter_select.gd`**

```gdscript
class_name StarterSelect
extends CanvasLayer

signal starter_chosen(dex_number: int)

const DEX_NUMBERS := [1, 4, 7]   # Bulbasaur, Charmander, Squirtle
var _selected: int = 0

func _input(event):
    if event.is_action_pressed("ui_right"):
        _selected = (_selected + 1) % 3
        _update_cursor()
    elif event.is_action_pressed("ui_left"):
        _selected = (_selected - 1 + 3) % 3
        _update_cursor()
    elif event.is_action_pressed("ui_accept"):
        starter_chosen.emit(DEX_NUMBERS[_selected])
```

**`scenes/overworld/PokemonCenter.tscn` + `scripts/overworld/pokemon_center.gd`**

Scene tree:

```
PokemonCenter (Node2D, script=pokemon_center.gd)
├ Background (TextureRect — the cropped PC interior image, z=-1)
├ WallCollision (StaticBody2D with CollisionShape2Ds for the walls/counter)
├ Player (instance of scenes/overworld/Player.tscn)
├ Nurse (Area2D, group "blockers", script=nurse.gd)
└ ExitMat (Area2D, group "doors", script=door.gd with target=Overworld.tscn)
```

`pokemon_center.gd`:

```gdscript
extends Node2D

func _ready() -> void:
    $Player.apply_spawn(GameState.next_spawn)
    GameState.next_spawn = {}
    await SceneFade.fade_in()
```

**`scripts/overworld/nurse.gd`**

```gdscript
extends Area2D

func on_interact() -> void:
    await DialogSequence.new() \
        .say("Welcome to the POKéMON CENTER!") \
        .say("We restore your POKéMON to full health.") \
        .wait(0.3) \
        .call_fn(GameState.heal_party) \
        .say("…Done! We hope to see you again!") \
        .run()
```

**`scripts/overworld/door.gd`**

```gdscript
class_name Door
extends Area2D

@export var target_scene: PackedScene
@export var target_cell: Vector2i
@export var target_facing: int   # Direction enum

func on_enter(player: Node) -> void:
    GameState.next_spawn = {
        "scene": target_scene,
        "cell": target_cell,
        "facing": target_facing,
    }
    await SceneFade.fade_out()
    get_tree().change_scene_to_packed(target_scene)
```

**`tools/build_buildings_atlas.py`** — follows the pattern of `tools/build_frlg_atlas.py`. Two outputs:

- `assets/buildings/frlg/pc_exterior.png` (+ optional .tres TileSet for tile-grid embedding).
- `assets/maps/frlg/pc_interior.png` — cropped from the premade Maps sheet.

**`tests/unit/test_heal_and_spawn.gd`** — 6 new GUT tests (see Testing).

### Modified files

- `scripts/globals/game_state.gd`
  - Add `var next_spawn: Dictionary = {}`.
  - Add `func heal_party() -> void`.
  - Remove `_debug_seed_party()` and the `_ready()` call.

- `scripts/overworld/player.gd`
  - Extend `_unhandled_input`: on A press, find `blockers`-group node at `cell + Direction.vec(facing)`, call `on_interact()` if present. Already handles `is_moving` / `input_locked` guards.
  - New helper `apply_spawn(spawn: Dictionary) -> void` that sets `cell`, `facing`, and `position` atomically. Defensive: ignores `spawn` without the required keys.
  - Extend `_on_move_complete`: check `doors`-group nodes for `cell == target_cell`, call `on_enter(self)` if found.

- `scripts/overworld/overworld_bootstrap.gd`
  - On `_ready()`:
    1. If `GameState.next_spawn` is non-empty, call `player.apply_spawn(...)` and clear the spawn. Then `await SceneFade.fade_in()`.
    2. Else if `GameState.player_party.is_empty()`, instantiate the starter-pick modal as a child, lock player input, `await starter_chosen` → build `PokemonInstance` via `PokemonInstance.create` + `DefaultMovesets.for_species`, append to party, free the modal, unlock input.
    3. Else: normal start (returning from battle or first-boot with non-empty party — shouldn't happen after 2d but defensive).
  - Add the `PokemonCenter` holder node to the Overworld scene (handled in the .tscn edit, not in script).
  - Keep `_debug_heal_party` (H key) as dev-only with a `# TODO(pre-release):` marker. Guard against firing when a dialog is open.

- `scripts/overworld/trainer.gd`
  - No forced changes, but existing trainers already use the `blockers` group via `add_to_group("blockers")` — they can now opt into talkable behavior later by adding an `on_interact()` method. For Phase 2d, trainers remain sight-cone-only; no on_interact implementation yet.

- `scenes/overworld/Overworld.tscn`
  - Add `PokemonCenter` child Node2D holder with: a `Sprite2D` for the 4×4 building exterior, a `StaticBody2D` + `CollisionShape2D` sized for the 3×4 non-door area, and a `Door` Area2D child at the door cell. Door exports filled for `PokemonCenter.tscn`, target_cell = exit_mat cell inside the interior, target_facing = UP.

- `project.godot`
  - Register `SceneFade` at `*res://scenes/ui/SceneFade.tscn`.
  - Register `DialogBox` at `*res://scenes/ui/DialogBox.tscn`.

- `CLAUDE.md`
  - Update the Asset Reference section to mention `assets/buildings/` and `assets/maps/` directories.

### Key simplifying rules

- **One autoload per UI system** — `SceneFade`, `DialogBox`, `GameState`. Each is a single instance, called from anywhere without re-instantiation.
- **PackedScene as `next_spawn.scene`** — typed reference, preloaded by the caller (the door node), no string paths.
- **Single-background interior** — one TextureRect, one StaticBody2D with a small number of CollisionShape2Ds for walls/counter. No interior TileMapLayer.
- **Cell-based door detection** — doors trigger on `_tween_to` completion, not Area2D enter signals. Matches the turn-based grid feel and avoids physics timing issues.
- **`heal_party()` lives on GameState**, not on PokemonInstance or Nurse — single responsibility: mutate the party, no UI, no narration.
- **Starter-pick narration is minimal** — the modal's prompt label is the narration ("Choose your first POKéMON!"). No DialogBox involvement at pick time. Oak-style scripted cutscene is Phase 3+.

## Data flow

Four scenarios.

### A — First-boot starter pick

```
Overworld._ready():
    if not GameState.next_spawn.is_empty():
        player.apply_spawn(GameState.next_spawn)
        GameState.next_spawn = {}
        await SceneFade.fade_in()
        return
    if GameState.player_party.is_empty():
        var picker = preload(".../StarterSelect.tscn").instantiate()
        add_child(picker)
        player.input_locked = true
        var dex: int = await picker.starter_chosen
        picker.queue_free()
        player.input_locked = false
        var species := _starter_species_for(dex)
        var moves := DefaultMovesets.for_species(dex)
        GameState.player_party.append(PokemonInstance.create(species, 5, moves))
```

The receiving-scene spawn branch (first `if`) runs in preference to the starter-pick branch. Starter pick only runs on genuine first boot (GameState freshly autoloaded AND no pending spawn).

### B — Enter Pokémon Center

```
Player._on_move_complete(target_cell):
    cell = target_cell
    is_moving = false
    moved.emit(cell)
    for door in get_tree().get_nodes_in_group("doors"):
        if "cell" in door and door.cell == cell and door.has_method("on_enter"):
            door.on_enter(self)
            return

Door.on_enter(player):
    GameState.next_spawn = {
        "scene": target_scene,
        "cell": target_cell,
        "facing": target_facing,
    }
    await SceneFade.fade_out()
    get_tree().change_scene_to_packed(target_scene)

PokemonCenter._ready():
    player.apply_spawn(GameState.next_spawn)
    GameState.next_spawn = {}
    await SceneFade.fade_in()
```

Each `Door` node carries two pieces of cell info: a `cell: Vector2i` export for "where I live on the current map" (used by the player's detection loop) and `target_cell: Vector2i` for "where the player lands on the next map" (used inside `on_enter`). Both are always the door node's own data — the player's detection loop only reads `door.cell` of doors within its currently-active scene tree.

### C — Heal dialog

```
Player presses A:
    var target_cell = cell + Direction.vec(facing)
    for b in get_tree().get_nodes_in_group("blockers"):
        if "cell" in b and b.cell == target_cell and b.has_method("on_interact"):
            b.on_interact()
            return

Nurse.on_interact():
    await DialogSequence.new() \
        .say("Welcome to the POKéMON CENTER!") \
        .say("We restore your POKéMON to full health.") \
        .wait(0.3) \
        .call_fn(GameState.heal_party) \
        .say("…Done! We hope to see you again!") \
        .run()
```

`DialogSequence.run()` internally awaits each `.say` on `DialogBox.queue([text])`, which returns a signal that fires when the player dismisses the line with ui_accept.

### D — Exit Pokémon Center

```
Player._on_move_complete on the ExitMat cell:
    # Same doors-group loop as B.
    ExitMat.on_enter(self)

ExitMat.on_enter(player):
    # ExitMat is a Door with target_scene = Overworld.tscn,
    # target_cell = one-below-PC-door-cell, target_facing = Direction.DOWN.
    GameState.next_spawn = {...}
    await SceneFade.fade_out()
    get_tree().change_scene_to_packed(target_scene)

Overworld._ready():
    # Branch A first clause fires: apply_spawn + fade_in.
```

The exit-mat's `target_cell` is the tile *below* the PC door on the overworld. If it were the door cell itself, the player's spawn-on-door would re-trigger the door's `on_enter` → transition loop.

## UI layout

See the brainstorm mockups in `.superpowers/brainstorm/.../ui-layout.html`. Three screens:

1. **Starter-pick modal** — 3 side-by-side Poké Ball slots (Bulbasaur/Charmander/Squirtle), arrow-navigate, A confirm. Sky-blue background; slots have peach border styling matching PartyScreen.
2. **Pokémon Center exterior on overworld** — 4×4 red-roofed building on a grass tile cluster, door tile at bottom-center. Cell chosen during implementation (candidate: around (10, 4)).
3. **Pokémon Center interior** — full-viewport TextureRect with the premade PC interior as background, nurse behind the counter, dialog box bottom-anchored at 240×40.

## Edge cases

- **Spawn lands on a door cell and re-triggers the door.** Fix: exit-mat spawn is set to the tile BELOW the PC door, facing DOWN. Player never respawns on a door tile. Defensive secondary guard: `Door.on_enter` checks `player.just_spawned_at_this_cell` flag set in `apply_spawn` and cleared after the next input tick — prevents same-frame re-trigger even if someone mis-sets a spawn.
- **Starter-pick dismissed mid-load.** Impossible today: picker is synchronous, `player.input_locked = true` during the await.
- **First-boot happens AFTER a scene transition.** Can't: `next_spawn` branch runs before the empty-party branch. First boot has both conditions empty; mid-game scene loads set `next_spawn` so starter-pick is skipped.
- **`heal_party()` on empty party.** No-op (for loop over nothing). Defensive.
- **Dialog queued while another dialog is open.** `DialogBox.queue()` awaits the current `closed` signal, then starts the new sequence. Callers don't need to check.
- **Player moves during dialog.** `DialogBox` opens → `player.input_locked = true` via group lookup; closes → `input_locked = false`. Same pattern used by PartyScreen.
- **Fade-in before scene is ready.** `await SceneFade.fade_in()` is called by `_ready()`, so the scene tree is built. No race.
- **Scene transition attempted during battle.** Can't: doors fire from `Player._on_move_complete`; `input_locked` is true during battle, so no movement is possible.
- **H debug key during a dialog.** `_debug_heal_party` first-line guard: `if DialogBox.is_open() or player.input_locked: return`.
- **Starter-pick for invalid dex number.** Impossible: modal only offers 1/4/7.
- **`next_spawn.scene` is null.** Overworld's `_ready()` falls through to the normal start cell (or the starter pick if party is empty).
- **Nurse interacted while party is already full HP.** No branch; same sequence runs. `heal_party()` is idempotent. Matches FR/LG.
- **Trainer in the `blockers` group doesn't define `on_interact`.** Fine — interact check uses `has_method("on_interact")`. Non-talkable blockers simply aren't interactable.

## Testing

### GUT unit tests — `tests/unit/test_heal_and_spawn.gd`

1. `GameState.heal_party()` restores `current_hp` to `max_hp()` for every party member. Set all to HP 1 + one to HP 0, heal, confirm all at max.
2. `heal_party()` clears `status`. Set one mon to `Enums.StatusCondition.BURN`, heal, confirm `NONE`.
3. `heal_party()` restores move PP. Decrement a move's `pp` to 0, heal, confirm restored to `max_pp`.
4. `heal_party()` on empty party is a no-op (doesn't crash).
5. `DialogSequence.new().say("a").wait(0.5).say("b").size()` returns 3 — builder chain accumulates correctly.
6. `Player.apply_spawn({cell: Vector2i(5, 5), facing: Direction.UP})` sets `cell = (5,5)`, `facing = Direction.UP`, `position = _cell_to_world((5,5))`. Instant, no tween.

Target: 6 new tests. Suite 50 → 56.

### Manual checkpoints

1. **First-boot starter pick** — clear any existing state (in-memory only, no save files), F5 Overworld → modal appears centered, three Poké Balls with species names, cursor starts on Bulbasaur, arrow-right moves to Charmander. Press A on Charmander → modal dismisses, overworld plays, P opens party showing Charmander at level 5 in slot 0.
2. **Walk to Pokémon Center** — navigate to the PC cell on the overworld map. Building sprite renders correctly with walls solid (player can't walk through them except at the door).
3. **Enter PC** — walk onto the door tile → fade to black → interior scene loads → fade back in → player at the exit-mat cell facing UP. No re-entry loop.
4. **Damage the party then heal** — walk out of PC → enter wild grass → battle → take damage (let a mon fall to low HP or faint) → escape or win → return to PC → talk to nurse → watch the three dialog lines with the pause in the middle → mon is at full HP (verify via party screen).
5. **Exit PC** — walk down onto exit mat → fade → overworld → player stands one tile below the PC door, facing DOWN. No re-entry loop.
6. **H debug still works outside dialog** — press H on overworld → party fully healed. Dev shortcut unaffected.
7. **H debug blocked during dialog** — in PC, start nurse dialog, press H mid-narration → H does nothing. Dialog continues normally.
8. **Trainer defeat persists across scene swap** — beat Trainer1, heal at PC, return to overworld. Trainer1 stays defeated (GameState.defeated_trainers persists — it's autoload).
9. **Dialog locks input** — during any dialog, press arrow keys → player doesn't move.
10. **Can't talk to nurse from across the counter** — stand two tiles below the nurse, press A. No dialog. Move one tile closer and re-press A. Dialog starts. (Verifies the one-tile-ahead facing check works.)

## Phase compatibility

- No save files exist yet (Phase 5+) — no migration concerns.
- `GameState.player_party`, `defeated_trainers`, etc. persist across `change_scene_to_packed` because they're autoload.
- `Player.tscn` is reused unchanged between Overworld and PokemonCenter — the spawn-in-place pattern makes it portable.
- Battle scene is orthogonal to 2d — battle overlays on whichever scene is active, and returns via `battle_ended.emit` without scene swaps.
- The 2c debug party seed in `GameState._ready()` is removed. The 2c test `_debug_heal_party` bind on H stays as dev-only.
- Species/Move data unchanged.

## What this unblocks

- **Phase 3+ Bag / items:** DialogBox + NPC interaction pattern both generalize to shopkeeper dialog in the Mart interior (same premade map sheet, same extraction tool).
- **Phase 3+ Multi-map:** `next_spawn` + `SceneFade` + `change_scene_to_packed` generalize to town/route transitions. Every new door just needs a `Door` node pointing at its target.
- **Phase 2e Evolution:** DialogBox is available for "{Name} is evolving!" narration if it runs outside battle.
- **Phase 3+ Save/load:** `GameState.next_spawn` + the current scene tree path are the last pieces needed to serialize "where is the player right now?"
- **Phase 3+ Oak cutscene / starter lab scene:** DialogSequence builder already supports scripted multi-line narration with embedded logic calls; adding an Oak NPC with a scripted sequence is a small extension.

## Open questions

None at time of approval.
