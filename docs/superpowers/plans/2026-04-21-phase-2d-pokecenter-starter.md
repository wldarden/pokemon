# Phase 2d — Pokémon Centers + Starter Selection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2c debug-seeded party and the H debug-heal key with their real counterparts: a first-boot starter-pick modal and an in-world Pokémon Center the player enters, talks to a nurse, and uses to heal.

**Architecture:** Three reusable systems (SceneFade autoload, DialogBox autoload, NPC-interact + Door pattern) plus two consumer features (StarterSelect modal, Pokémon Center). Interior scene uses the premade FR/LG map image as a single TextureRect background with a few hand-placed collision shapes — no interior tilemap. Scene transitions via Godot's `change_scene_to_packed` + a tiny `next_spawn` dict on `GameState`.

**Tech Stack:** Godot 4.6 + GDScript, GUT 9 for unit tests. Test suite starts at 50/50; target 56/56 after TDD step 2d.1.

**Spec:** [docs/superpowers/specs/2026-04-21-phase-2d-pokecenter-starter-design.md](../specs/2026-04-21-phase-2d-pokecenter-starter-design.md)

---

## File structure

**New:**

| File | Responsibility |
|---|---|
| `scripts/overworld/dialog_sequence.gd` | `DialogSequence` builder. Chainable `.say/.wait/.call_fn/.run`. Pure-logic builder state; `run()` awaits DialogBox. |
| `scripts/overworld/door.gd` | `Door extends Area2D`. Exports `target_scene`, `target_cell`, `target_facing`, `cell`. `on_enter(player)` fades out, swaps scenes. |
| `scripts/ui/scene_fade.gd` + `scenes/ui/SceneFade.tscn` | Autoload CanvasLayer (layer 100). `fade_out(d=0.25)` / `fade_in(d=0.25)` methods. |
| `scripts/ui/dialog_box.gd` + `scenes/ui/DialogBox.tscn` | Autoload CanvasLayer. Bottom-anchored 240×40 panel + Label. `queue(lines) -> Signal`. Typewriter + input-lock. |
| `scripts/ui/starter_select.gd` + `scenes/ui/StarterSelect.tscn` | Modal with 3 Poké Ball slots. `starter_chosen(dex_number)` signal. |
| `scripts/overworld/pokemon_center.gd` + `scenes/overworld/PokemonCenter.tscn` | Interior scene: TextureRect background, wall collision, player spawn, Nurse + ExitMat doors. |
| `scripts/overworld/nurse.gd` | Attached to Nurse node. `on_interact()` runs heal DialogSequence. |
| `tools/build_buildings_atlas.py` | Extracts PC exterior from Buildings.png + PC interior from Maps sheet. Chroma-keys exterior. |
| `assets/buildings/frlg/pc_exterior.png` | Generated 96×70 transparent sprite. |
| `assets/maps/frlg/pc_interior.png` | Generated 240×160 single background. |
| `tests/unit/test_heal_and_spawn.gd` | 6 GUT unit tests for heal_party, apply_spawn, DialogSequence. |

**Modified:**

| File | Change |
|---|---|
| `scripts/globals/game_state.gd` | Add `next_spawn: Dictionary`, `heal_party()`. Remove `_debug_seed_party()` and its `_ready` call (in step 2d.6 — kept until StarterSelect lands so the game stays playable). |
| `scripts/overworld/player.gd` | Extend `_unhandled_input` for A-press interact. Extend `_on_move_complete` for door-on-step. Add `apply_spawn(dict)`. |
| `scripts/overworld/overworld_bootstrap.gd` | `_ready` picks between spawn-from-next_spawn / starter-pick-modal / normal-start. Guards H debug key against dialog-open. |
| `scenes/overworld/Overworld.tscn` | Adds `PokemonCenter` holder (sprite + collision + Door). |
| `project.godot` | Adds `SceneFade` and `DialogBox` autoloads. |
| `CLAUDE.md` | Asset Reference section mentions `assets/buildings/` and `assets/maps/`. |

---

## Step decomposition

Eight sub-steps. Each produces a single-commit's worth of work.

1. `2d.1` — Pure helpers + unit tests (TDD)
2. `2d.2` — SceneFade autoload
3. `2d.3` — DialogBox autoload
4. `2d.4` — NPC interact + Door class (Player.gd extensions + Door)
5. `2d.5` — Buildings asset extraction tool + generated assets
6. `2d.6` — StarterSelect modal + first-boot wiring (removes debug seed)
7. `2d.7` — PokemonCenter interior scene + Nurse heal flow
8. `2d.8` — PC exterior on Overworld + wire Door → interior

---

## Task 2d.1: Pure helpers + unit tests (TDD)

**Files:**
- Modify: `scripts/globals/game_state.gd`
- Modify: `scripts/overworld/player.gd`
- Create: `scripts/overworld/dialog_sequence.gd`
- Create: `tests/unit/test_heal_and_spawn.gd`

- [ ] **Step 1 — Write failing tests**

Create `tests/unit/test_heal_and_spawn.gd`:

```gdscript
extends GutTest
## Phase 2d — heal_party, Player.apply_spawn, DialogSequence builder.

const BULBASAUR  := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER := preload("res://data/species/004_charmander.tres")
const TACKLE     := preload("res://data/moves/tackle.tres")

# ---- GameState.heal_party ------------------------------------------------

func _make_damaged_mon() -> PokemonInstance:
	var m := PokemonInstance.create(BULBASAUR, 10, [TACKLE])
	m.current_hp = 1
	m.status = Enums.StatusCondition.BURN
	m.moves[0].pp = 0
	return m

func test_heal_party_restores_hp_to_max() -> void:
	var a := _make_damaged_mon()
	var b := PokemonInstance.create(CHARMANDER, 8, [TACKLE])
	b.current_hp = 0   # fainted
	GameState.player_party = [a, b]
	GameState.heal_party()
	assert_eq(a.current_hp, a.max_hp(), "damaged mon at full")
	assert_eq(b.current_hp, b.max_hp(), "fainted mon revived")

func test_heal_party_clears_status() -> void:
	var a := _make_damaged_mon()
	GameState.player_party = [a]
	GameState.heal_party()
	assert_eq(a.status, Enums.StatusCondition.NONE, "status cleared to NONE")

func test_heal_party_restores_pp() -> void:
	var a := _make_damaged_mon()
	GameState.player_party = [a]
	GameState.heal_party()
	assert_eq(a.moves[0].pp, a.moves[0].max_pp, "PP restored")

func test_heal_party_empty_is_noop() -> void:
	GameState.player_party = []
	GameState.heal_party()   # must not crash
	assert_eq(GameState.player_party.size(), 0)

# ---- DialogSequence builder ----------------------------------------------

func test_dialog_sequence_builder_accumulates_steps() -> void:
	var seq := DialogSequence.new() \
		.say("hello") \
		.wait(0.5) \
		.say("world")
	assert_eq(seq.size(), 3, "three steps queued")

# ---- Player.apply_spawn --------------------------------------------------

func test_player_apply_spawn_sets_cell_and_facing() -> void:
	# Player.apply_spawn is tested via a detached instance — no scene tree needed
	# because the function only mutates internal vars.
	var script := load("res://scripts/overworld/player.gd")
	var p := script.new()
	p.apply_spawn({"cell": Vector2i(5, 5), "facing": Direction.UP})
	assert_eq(p.cell, Vector2i(5, 5))
	assert_eq(p.facing, Direction.UP)
	p.free()
```

- [ ] **Step 2 — Run tests, verify they fail**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: 6 new failures. `GameState.heal_party` undefined, `DialogSequence` class not found, `Player.apply_spawn` undefined. Suite still 50 passing from existing tests.

- [ ] **Step 3 — Add `heal_party` to `GameState`**

Edit `scripts/globals/game_state.gd`. Add just below the existing `pokedex_caught: Dictionary = {}` line:

```gdscript

## Spawn intent across scene transitions. Keys: scene (PackedScene),
## cell (Vector2i), facing (int from Direction enum). Set by the outgoing
## door, consumed and cleared by the receiving scene's _ready().
var next_spawn: Dictionary = {}

## Restore every party member to full HP, clear status, restore all PP.
## Idempotent — safe to call on a fully-healthy party. No-op on empty.
func heal_party() -> void:
	for mon in player_party:
		if mon == null:
			continue
		mon.current_hp = mon.max_hp()
		mon.status = Enums.StatusCondition.NONE
		for slot in mon.moves:
			slot.pp = slot.max_pp
```

- [ ] **Step 4 — Create `scripts/overworld/dialog_sequence.gd`**

```gdscript
class_name DialogSequence
extends RefCounted
## Phase 2d — fluent builder for scripted overworld narration.
##
## Usage:
##   await DialogSequence.new() \
##       .say("Welcome!") \
##       .wait(0.3) \
##       .call_fn(func(): GameState.heal_party()) \
##       .say("Done.") \
##       .run()
##
## Each step is awaited in order. `say` delegates to the DialogBox autoload.

var _steps: Array = []

func say(text: String) -> DialogSequence:
	_steps.append({"kind": "say", "text": text})
	return self

func wait(seconds: float) -> DialogSequence:
	_steps.append({"kind": "wait", "seconds": seconds})
	return self

func call_fn(callable: Callable) -> DialogSequence:
	_steps.append({"kind": "call", "fn": callable})
	return self

func size() -> int:
	return _steps.size()

## Run the queued steps sequentially. Awaits DialogBox.queue for say lines,
## Timer for waits, and invokes callables synchronously. Returns when done.
func run() -> void:
	for step in _steps:
		match step["kind"]:
			"say":
				await DialogBox.queue([step["text"]])
			"wait":
				await Engine.get_main_loop().create_timer(step["seconds"]).timeout
			"call":
				var fn: Callable = step["fn"]
				fn.call()
```

Note: `DialogBox` is the autoload added in 2d.3. For 2d.1 the builder's `size()` is what we test — `run()` isn't exercised until later steps have the autoload available. The reference to `DialogBox` is a free identifier (resolved at runtime), so the script parses fine in 2d.1 without the autoload existing yet.

- [ ] **Step 5 — Add `apply_spawn` to `Player`**

Edit `scripts/overworld/player.gd`. Add this method just above the existing `func _ready() -> void:` line:

```gdscript
## Phase 2d — place the player at a specific cell + facing without a tween.
## Called by scenes at _ready() when consuming GameState.next_spawn.
##
## `spawn` dict keys:
##   cell: Vector2i (required)
##   facing: int    (optional; defaults to current facing)
func apply_spawn(spawn: Dictionary) -> void:
	if not spawn.has("cell"):
		return
	cell = spawn["cell"]
	if spawn.has("facing"):
		facing = int(spawn["facing"])
	position = _cell_to_world(cell)

```

- [ ] **Step 6 — Run tests, verify pass**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: all 6 new tests pass. Suite total **56/56**.

- [ ] **Step 7 — Commit**

```bash
git add scripts/globals/game_state.gd \
        scripts/overworld/dialog_sequence.gd \
        scripts/overworld/player.gd \
        tests/unit/test_heal_and_spawn.gd
# Add any newly-generated .uid sidecars
git add -A scripts/overworld/*.uid tests/unit/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): heal_party + apply_spawn + DialogSequence builder

- GameState.heal_party() — restore every party member's HP, status, PP.
  Idempotent; no-op on empty party.
- GameState.next_spawn: Dictionary — cross-scene spawn intent (scene,
  cell, facing). Unused yet; consumed by PokemonCenter + Overworld in
  later steps.
- Player.apply_spawn(spawn) — set cell/facing/position without tween.
  Used by scenes at _ready() when consuming next_spawn.
- DialogSequence builder (scripts/overworld/dialog_sequence.gd) with
  chainable .say/.wait/.call_fn and a run() that awaits each step.
  Consumed by the nurse in 2d.7.
- 6 new GUT tests: heal HP/status/PP/empty-no-op, DialogSequence step
  accumulation, Player.apply_spawn state mutation.

Suite: 56/56 on the pure-function layer. Integration + scene work
lands in 2d.2 onward.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.2: SceneFade autoload

**Files:**
- Create: `scripts/ui/scene_fade.gd`
- Create: `scenes/ui/SceneFade.tscn`
- Modify: `project.godot`

No tests — this is pure UI infrastructure. Smoke-verified via scene load.

- [ ] **Step 1 — Create `scripts/ui/scene_fade.gd`**

```gdscript
extends CanvasLayer
## Phase 2d autoload singleton. Persistent black-rect overlay for fade
## transitions. Layer = 100 so it overlays everything including battle.

@onready var rect: ColorRect = $Rect

func _ready() -> void:
	rect.modulate.a = 0.0

## Fade the screen to black over `duration` seconds. Awaitable.
func fade_out(duration: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, duration)
	await tw.finished

## Fade the screen from black back to transparent. Awaitable.
func fade_in(duration: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, duration)
	await tw.finished
```

- [ ] **Step 2 — Create `scenes/ui/SceneFade.tscn`**

```
[gd_scene load_steps=2 format=3 uid="uid://bphase2d001"]

[ext_resource type="Script" path="res://scripts/ui/scene_fade.gd" id="1_script"]

[node name="SceneFade" type="CanvasLayer"]
layer = 100
script = ExtResource("1_script")

[node name="Rect" type="ColorRect" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
offset_right = 240.0
offset_bottom = 160.0
color = Color(0, 0, 0, 1)
mouse_filter = 2
```

- [ ] **Step 3 — Register autoload in `project.godot`**

Edit `project.godot`. Find the `[autoload]` section and extend it:

```
[autoload]

GameState="*res://scripts/globals/game_state.gd"
SceneFade="*res://scenes/ui/SceneFade.tscn"
```

The `*` prefix means "singleton" — available globally as `SceneFade`.

- [ ] **Step 4 — Smoke test**

Run the test suite (no regression expected since no behavior changed):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56**.

Run the overworld scene to verify no parse errors:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/Overworld.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: no Parse Error / Invalid call / Identifier not declared in the output.

- [ ] **Step 5 — Commit**

```bash
git add scripts/ui/scene_fade.gd scenes/ui/SceneFade.tscn project.godot
git add -A scripts/ui/*.uid scenes/ui/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): SceneFade autoload for scene-transition fades

- scenes/ui/SceneFade.tscn + scripts/ui/scene_fade.gd: autoload
  CanvasLayer at layer=100 with a single black ColorRect covering the
  240×160 viewport. Registered as `SceneFade` in project.godot.
- fade_out(duration=0.25) and fade_in(duration=0.25) are awaitable:
  tween the rect's alpha, return when complete. Callable from any
  scene via the autoload.

Consumed in 2d.4 by the Door class (fade_out before change_scene_to_packed)
and in 2d.7/2d.8 by the PokemonCenter and Overworld scenes (fade_in on
_ready after a scene swap).

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.3: DialogBox autoload

**Files:**
- Create: `scripts/ui/dialog_box.gd`
- Create: `scenes/ui/DialogBox.tscn`
- Modify: `project.godot`

- [ ] **Step 1 — Create `scripts/ui/dialog_box.gd`**

```gdscript
extends CanvasLayer
## Phase 2d autoload singleton. Reusable overworld dialog box with
## typewriter effect. Not used inside the Battle scene — battle has its
## own dialog with the same CHAR_PRINT_DELAY pacing.
##
## Public API:
##   queue(lines: Array[String]) -> Signal    # returns `closed` signal
##   is_open() -> bool

signal closed

const CHAR_PRINT_DELAY := 0.03
const DIALOG_LINGER := 0.3

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label

var _open: bool = false
var _advance_requested: bool = false

func _ready() -> void:
	panel.visible = false

## Display a sequence of dialog lines, one at a time, waiting for
## ui_accept between each. Returns the `closed` signal so callers can
## `await DialogBox.queue([...])`.
func queue(lines: Array[String]) -> Signal:
	# If already open, wait for the current sequence to finish first.
	if _open:
		await closed
	_run(lines)
	return closed

func is_open() -> bool:
	return _open

# ---- Internal -------------------------------------------------------------

func _run(lines: Array[String]) -> void:
	_open = true
	panel.visible = true
	_lock_player_input(true)
	for line in lines:
		await _print_line(line)
	panel.visible = false
	_lock_player_input(false)
	_open = false
	closed.emit()

func _print_line(line: String) -> void:
	label.text = line
	label.visible_ratio = 0.0
	var total_chars: int = line.length()
	if total_chars == 0:
		return
	var tw := create_tween()
	tw.tween_property(label, "visible_ratio", 1.0, CHAR_PRINT_DELAY * total_chars)
	# Typewriter can be skipped by pressing ui_accept.
	_advance_requested = false
	while tw.is_running():
		if _advance_requested:
			tw.kill()
			label.visible_ratio = 1.0
			break
		await get_tree().process_frame
	# After typewriter finishes, wait for another ui_accept to advance.
	_advance_requested = false
	while not _advance_requested:
		await get_tree().process_frame
	# Small linger so rapid A-presses don't skip the NEXT line.
	await get_tree().create_timer(DIALOG_LINGER).timeout

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_accept"):
		_advance_requested = true
		get_viewport().set_input_as_handled()

func _lock_player_input(locked: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if "input_locked" in p:
			p.input_locked = locked
```

- [ ] **Step 2 — Add Player to the "player" group**

Edit `scripts/overworld/player.gd`. Find `func _ready() -> void:` and add `add_to_group("player")` as the very first line inside it:

```gdscript
func _ready() -> void:
	add_to_group("player")
	cell = start_cell
	# ... existing body below ...
```

This lets the DialogBox autoload find the player from any scene via `get_tree().get_nodes_in_group("player")`.

- [ ] **Step 3 — Create `scenes/ui/DialogBox.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://bphase2d002"]

[ext_resource type="Script" path="res://scripts/ui/dialog_box.gd" id="1_script"]

[sub_resource type="StyleBoxFlat" id="sb_panel"]
bg_color = Color(0.972, 0.972, 0.910, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.180, 0.180, 0.313, 1)

[node name="DialogBox" type="CanvasLayer"]
layer = 50
script = ExtResource("1_script")

[node name="Panel" type="Panel" parent="."]
offset_left = 0.0
offset_top = 120.0
offset_right = 240.0
offset_bottom = 160.0
theme_override_styles/panel = SubResource("sb_panel")
mouse_filter = 2

[node name="Label" type="Label" parent="Panel"]
offset_left = 6.0
offset_top = 4.0
offset_right = 234.0
offset_bottom = 36.0
theme_override_colors/font_color = Color(0.180, 0.180, 0.313, 1)
theme_override_font_sizes/font_size = 8
autowrap_mode = 2
text = ""
```

- [ ] **Step 4 — Register autoload in `project.godot`**

Extend the `[autoload]` section:

```
[autoload]

GameState="*res://scripts/globals/game_state.gd"
SceneFade="*res://scenes/ui/SceneFade.tscn"
DialogBox="*res://scenes/ui/DialogBox.tscn"
```

- [ ] **Step 5 — Smoke test**

Tests:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56** (no regressions).

Overworld load:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/Overworld.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: clean (no Parse Error / Invalid call / Identifier not declared).

- [ ] **Step 6 — Commit**

```bash
git add scripts/ui/dialog_box.gd scenes/ui/DialogBox.tscn scripts/overworld/player.gd project.godot
git add -A scripts/ui/*.uid scenes/ui/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): DialogBox autoload for overworld typewriter dialog

- scenes/ui/DialogBox.tscn + scripts/ui/dialog_box.gd: autoload
  CanvasLayer at layer=50 with a bottom-anchored 240×40 panel. Typewriter
  effect (CHAR_PRINT_DELAY = 0.03, same pacing as battle). ui_accept
  skips the typewriter, then ui_accept again advances to the next line.
  0.3s linger between lines so rapid A-presses don't skip ahead.
- queue(lines: Array[String]) -> Signal: returns `closed` so callers can
  `await DialogBox.queue([...])`. If already open, awaits the current
  sequence to complete before starting the new one.
- Locks player input via the "player" group while open. Player.gd now
  adds itself to that group in _ready().
- Battle's own dialog is untouched per the spec scope call.

Consumed in 2d.7 by the Nurse via DialogSequence.run().

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.4: NPC interact + Door class

**Files:**
- Modify: `scripts/overworld/player.gd`
- Create: `scripts/overworld/door.gd`

No tests this step — behavior is exercised by the StarterSelect + PC consumers in later steps. Manual verification: the overworld still loads cleanly, existing trainers (blockers without `on_interact`) still block movement as before.

- [ ] **Step 1 — Extend `Player._on_move_complete` for door detection**

Edit `scripts/overworld/player.gd`. Find the existing `_on_move_complete` function:

```gdscript
func _on_move_complete(target_cell: Vector2i) -> void:
	cell = target_cell
	is_moving = false
	moved.emit(cell)
	# If the key is released, _process() will snap to idle on the next frame;
	# if still held, it will immediately schedule the next step.
```

Replace it with:

```gdscript
func _on_move_complete(target_cell: Vector2i) -> void:
	cell = target_cell
	is_moving = false
	moved.emit(cell)

	# Phase 2d: doors group members with `cell` and `on_enter(player)`
	# trigger a scene transition when stepped on.
	for door in get_tree().get_nodes_in_group("doors"):
		if "cell" in door and door.cell == cell and door.has_method("on_enter"):
			door.on_enter(self)
			return

	# If the key is released, _process() will snap to idle on the next frame;
	# if still held, it will immediately schedule the next step.
```

- [ ] **Step 2 — Extend `Player._unhandled_input` for interact-on-A**

Find the existing `_unhandled_input` (added in 2c.4 for the P keybind). It currently handles KEY_P only:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if input_locked or is_moving:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		party_screen_requested.emit()
		get_viewport().set_input_as_handled()
```

Replace with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if input_locked or is_moving:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		party_screen_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_try_interact()

## Phase 2d: press A facing a "blockers"-group node that has an
## on_interact() method → call it. Used by NPCs (nurse, etc.).
func _try_interact() -> void:
	var target_cell: Vector2i = cell + DIR_VEC[facing]
	for b in get_tree().get_nodes_in_group("blockers"):
		if "cell" in b and b.cell == target_cell and b.has_method("on_interact"):
			b.on_interact()
			get_viewport().set_input_as_handled()
			return
```

- [ ] **Step 3 — Create `scripts/overworld/door.gd`**

```gdscript
class_name Door
extends Area2D
## Phase 2d — scene-transition trigger. Place on a cell in the "doors"
## group. When the player's move completes on that cell, Player invokes
## `on_enter(player)`, which fades out and swaps to `target_scene`.
##
## The receiving scene's _ready() reads GameState.next_spawn to place
## the player at `target_cell` facing `target_facing`.

## Where this door lives on its own map. Compared with player.cell.
@export var cell: Vector2i = Vector2i.ZERO

## PackedScene to swap into when the player enters this cell.
@export var target_scene: PackedScene

## Where the player should appear in the target scene.
@export var target_cell: Vector2i = Vector2i.ZERO

## Facing direction in the target scene (Direction enum values 0..3).
@export_enum("down:0", "up:1", "left:2", "right:3") var target_facing: int = 0

func _ready() -> void:
	add_to_group("doors")

## Called by Player._on_move_complete when the player steps onto `cell`.
## Fades the screen, sets GameState.next_spawn, and triggers the swap.
func on_enter(_player: Node) -> void:
	if target_scene == null:
		push_error("Door at %s has no target_scene." % cell)
		return
	GameState.next_spawn = {
		"scene": target_scene,
		"cell": target_cell,
		"facing": target_facing,
	}
	await SceneFade.fade_out()
	get_tree().change_scene_to_packed(target_scene)
```

- [ ] **Step 4 — Smoke test**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56**, unchanged.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/Overworld.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: clean.

Manual check (optional): press A on the overworld while facing an empty tile and while facing Trainer1. Nothing should happen (no `on_interact` on trainers yet). Player movement + party screen + trainer spotting should all work unchanged.

- [ ] **Step 5 — Commit**

```bash
git add scripts/overworld/player.gd scripts/overworld/door.gd
git add -A scripts/overworld/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): NPC interact + Door class

- Player._unhandled_input extended: on ui_accept (A press), compute the
  tile one step in `facing`, find any blockers-group node at that cell
  with an on_interact() method, call it. Unused this step — trainers
  don't implement on_interact yet; nurse will in 2d.7.
- Player._on_move_complete extended: after the move lands, scan the
  "doors" group for any node whose cell == target_cell and has
  on_enter(player) — call it. Again unused this step; exterior PC door
  lands in 2d.8.
- scripts/overworld/door.gd: new Door class (Area2D). Exports cell,
  target_scene, target_cell, target_facing. Self-registers in the
  "doors" group on _ready. on_enter sets GameState.next_spawn, awaits
  SceneFade.fade_out, and calls change_scene_to_packed.

Existing trainers in the "blockers" group remain non-talkable (they
don't implement on_interact). Regressions: none; suite 56/56.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.5: Buildings asset extraction tool

**Files:**
- Create: `tools/build_buildings_atlas.py`
- Create: `assets/buildings/frlg/pc_exterior.png` (generated)
- Create: `assets/maps/frlg/pc_interior.png` (generated)

No tests. This is tooling + generated assets. Verification is visual inspection of the output PNGs.

- [ ] **Step 1 — Create `tools/build_buildings_atlas.py`**

```python
#!/usr/bin/env python3
"""Phase 2d: extract the Pokémon Center exterior sprite from the Buildings
sheet and the Pokémon Center interior from the pre-rendered Maps sheet.

Outputs:
  - assets/buildings/frlg/pc_exterior.png
      ~96×70, transparent background (chroma-keyed from sheet white).
  - assets/maps/frlg/pc_interior.png
      240×160, single-screen FR/LG PC interior, ready as a TextureRect
      background for PokemonCenter.tscn.

Coordinates were measured against the Spriters Resource rips:
  Buildings.png ........ "Pokemon Center" label at (~520, 248). Sprite
                         body spans x=496..592, y=244..314.
  Pokemon Center _ Mart.png .... "Pokémon Center (1F)" panel, 240×160
                                 interior at (0, 16, 240, 176).

Mart + Pokémart interior coords are recorded as comments for future phases.
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
PC_INTERIOR_RECT = (0,   16,  240, 176)   # Pokemon Center _ Mart.png

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
    print(f"PC exterior: {pc_ext.size} → {pc_ext_path.relative_to(REPO)}")

    # Interior: straight crop. No chroma-key — it's a solid interior.
    maps = Image.open(SRC_MAPS)
    pc_int = maps.crop(PC_INTERIOR_RECT)
    pc_int_path = OUT_MAPS_DIR / "pc_interior.png"
    pc_int.save(pc_int_path)
    print(f"PC interior: {pc_int.size} → {pc_int_path.relative_to(REPO)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2 — Run the tool**

```bash
python3 tools/build_buildings_atlas.py
```

Expected output:

```
PC exterior: (96, 70) → assets/buildings/frlg/pc_exterior.png
PC interior: (240, 160) → assets/maps/frlg/pc_interior.png
```

- [ ] **Step 3 — Inspect the generated PNGs**

```bash
python3 -c "
from PIL import Image
for p in ['assets/buildings/frlg/pc_exterior.png', 'assets/maps/frlg/pc_interior.png']:
    im = Image.open(p)
    print(p, im.size, im.mode)
"
```

Expected: exterior is `(96, 70) RGBA`, interior is `(240, 160) RGB` or `RGBA`.

Open the files in your image viewer. Confirm the exterior shows the red-roofed PC with transparent surroundings; interior shows the full PC (1F) room with nurse, counter, healing machine, PC corner, and exit mat visible.

If the exterior crop is slightly off (e.g. chops the door or includes extra neighbor pixels), adjust `PC_EXTERIOR_RECT` in `tools/build_buildings_atlas.py` and rerun. Target: building is cleanly cropped with ~4–8 px transparent margin.

- [ ] **Step 4 — Smoke test + commit**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56** unchanged.

```bash
git add tools/build_buildings_atlas.py \
        assets/buildings/frlg/pc_exterior.png \
        assets/maps/frlg/pc_interior.png
# Any .uid sidecars Godot generated for the PNG imports
git add -A assets/buildings/frlg/*.uid assets/maps/frlg/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): Buildings + Maps asset extraction tool + PC sprites

- tools/build_buildings_atlas.py: extracts the Pokémon Center exterior
  from the FR/LG Buildings.png rip and the 240×160 PC interior from the
  Maps rip. Coordinates verified against Spriters Resource layout
  (exterior at 496,244–592,314; interior at 0,16–240,176). Exterior
  gets white chroma-keyed to transparency; interior is a straight crop.
- assets/buildings/frlg/pc_exterior.png: 96×70 transparent PNG with the
  red-roofed PC building.
- assets/maps/frlg/pc_interior.png: 240×160 single-screen interior
  matching the game's native resolution exactly.

Tool records MART and POKéMART interior coords in comments for when
Phase 3+ adds shopping.

Consumed in 2d.7 (interior scene background) and 2d.8 (overworld
building sprite).

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.6: StarterSelect modal + first-boot wiring

**Files:**
- Create: `scripts/ui/starter_select.gd`
- Create: `scenes/ui/StarterSelect.tscn`
- Modify: `scripts/globals/game_state.gd` (remove debug seed)
- Modify: `scripts/overworld/overworld_bootstrap.gd` (first-boot flow)

- [ ] **Step 1 — Create `scripts/ui/starter_select.gd`**

```gdscript
class_name StarterSelect
extends CanvasLayer
## Phase 2d — first-boot modal. Three Poké Ball slots; arrow-nav; A confirm.
## No cancel. Emits `starter_chosen(dex_number: int)` on pick.

signal starter_chosen(dex_number: int)

const DEX_NUMBERS: Array[int] = [1, 4, 7]  # Bulbasaur, Charmander, Squirtle

@onready var slots: Array[Panel] = [
	$Root/Slots/Slot1, $Root/Slots/Slot2, $Root/Slots/Slot3,
]

var _selected: int = 0

func _ready() -> void:
	_update_cursor()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % 3
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + 3) % 3
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		starter_chosen.emit(DEX_NUMBERS[_selected])
		get_viewport().set_input_as_handled()

func _update_cursor() -> void:
	for i in slots.size():
		slots[i].self_modulate = Color(1, 1, 0.125, 1) if i == _selected else Color(1, 1, 1, 1)
```

- [ ] **Step 2 — Create `scenes/ui/StarterSelect.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://bphase2d003"]

[ext_resource type="Script" path="res://scripts/ui/starter_select.gd" id="1_script"]

[sub_resource type="StyleBoxFlat" id="sb_slot"]
bg_color = Color(0.972, 0.972, 0.910, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.180, 0.180, 0.313, 1)

[node name="StarterSelect" type="CanvasLayer"]
layer = 60
script = ExtResource("1_script")

[node name="Root" type="Control" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
offset_right = 240.0
offset_bottom = 160.0

[node name="Background" type="ColorRect" parent="Root"]
anchor_right = 1.0
anchor_bottom = 1.0
offset_right = 240.0
offset_bottom = 160.0
color = Color(0.596, 0.847, 0.941, 1)

[node name="Title" type="Label" parent="Root"]
offset_left = 0.0
offset_top = 8.0
offset_right = 240.0
offset_bottom = 22.0
theme_override_font_sizes/font_size = 8
horizontal_alignment = 1
text = "Choose your first POKéMON!"

[node name="Slots" type="Control" parent="Root"]
offset_left = 0.0
offset_top = 40.0
offset_right = 240.0
offset_bottom = 130.0

[node name="Slot1" type="Panel" parent="Root/Slots"]
offset_left = 18.0
offset_top = 0.0
offset_right = 78.0
offset_bottom = 90.0
theme_override_styles/panel = SubResource("sb_slot")

[node name="Name1" type="Label" parent="Root/Slots/Slot1"]
offset_left = 0.0
offset_top = 70.0
offset_right = 60.0
offset_bottom = 82.0
theme_override_font_sizes/font_size = 8
horizontal_alignment = 1
text = "BULBASAUR"

[node name="Slot2" type="Panel" parent="Root/Slots"]
offset_left = 90.0
offset_top = 0.0
offset_right = 150.0
offset_bottom = 90.0
theme_override_styles/panel = SubResource("sb_slot")

[node name="Name2" type="Label" parent="Root/Slots/Slot2"]
offset_left = 0.0
offset_top = 70.0
offset_right = 60.0
offset_bottom = 82.0
theme_override_font_sizes/font_size = 8
horizontal_alignment = 1
text = "CHARMANDER"

[node name="Slot3" type="Panel" parent="Root/Slots"]
offset_left = 162.0
offset_top = 0.0
offset_right = 222.0
offset_bottom = 90.0
theme_override_styles/panel = SubResource("sb_slot")

[node name="Name3" type="Label" parent="Root/Slots/Slot3"]
offset_left = 0.0
offset_top = 70.0
offset_right = 60.0
offset_bottom = 82.0
theme_override_font_sizes/font_size = 8
horizontal_alignment = 1
text = "SQUIRTLE"

[node name="Hint" type="Label" parent="Root"]
offset_left = 0.0
offset_top = 138.0
offset_right = 240.0
offset_bottom = 152.0
theme_override_font_sizes/font_size = 8
horizontal_alignment = 1
text = "Arrow keys / A to confirm"
```

- [ ] **Step 3 — Remove debug seed from `GameState`**

Edit `scripts/globals/game_state.gd`. Delete both the `_ready` function AND the `_debug_seed_party` helper:

```gdscript
# BEFORE — DELETE THESE:

func _ready() -> void:
	if player_party.is_empty():
		_debug_seed_party()

# TODO(2d): remove when starter selection + catching land.
func _debug_seed_party() -> void:
	var BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
	var CHARMANDER  := preload("res://data/species/004_charmander.tres")
	var SQUIRTLE    := preload("res://data/species/007_squirtle.tres")

	var bulb := PokemonInstance.create(BULBASAUR, 7, DefaultMovesets.for_species(1))
	var char_mon := PokemonInstance.create(CHARMANDER, 5, DefaultMovesets.for_species(4))
	var squirt := PokemonInstance.create(SQUIRTLE, 5, DefaultMovesets.for_species(7))
	# Seed one member at mid-HP so low-HP UI can be eyeballable immediately.
	char_mon.current_hp = max(1, char_mon.max_hp() / 2)

	player_party = [bulb, char_mon, squirt]
```

The file should no longer have any `_ready` or `_debug_seed_party` function. The existing `heal_party()` from 2d.1 stays.

- [ ] **Step 4 — Wire first-boot flow in `overworld_bootstrap.gd`**

Edit `scripts/overworld/overworld_bootstrap.gd`. Find the existing `_ready` function and locate the point where overworld setup finishes (after encounter-zone signal wiring, after trainer setup). Add the first-boot logic at the very start of `_ready`:

```gdscript
const STARTER_SELECT := preload("res://scenes/ui/StarterSelect.tscn")

const STARTER_SPECIES := {
	1: preload("res://data/species/001_bulbasaur.tres"),
	4: preload("res://data/species/004_charmander.tres"),
	7: preload("res://data/species/007_squirtle.tres"),
}
```

Place those new consts near the top of the file with the existing `PARTY_SCREEN := preload(...)` and `PartyScreenScript := preload(...)` lines.

Then inside `_ready`, as the FIRST substantive block (before any tile painting or signal wiring):

```gdscript
func _ready() -> void:
	# Phase 2d: resume from a scene transition OR run first-boot starter pick.
	if not GameState.next_spawn.is_empty():
		$Player.apply_spawn(GameState.next_spawn)
		GameState.next_spawn = {}
		await SceneFade.fade_in()
	elif GameState.player_party.is_empty():
		await _run_starter_pick()

	# ---- Existing body below (tile painting, signal wiring, etc.) ----
	# ... keep everything that was already here ...
```

Add the helper at the bottom of the file:

```gdscript
## Phase 2d first-boot flow: spawn the starter-pick modal, await the
## player's choice, build the chosen Pokémon and append it to the party,
## then clean up.
func _run_starter_pick() -> void:
	var picker: StarterSelect = STARTER_SELECT.instantiate()
	add_child(picker)
	$Player.input_locked = true
	var dex: int = await picker.starter_chosen
	picker.queue_free()
	var species: Species = STARTER_SPECIES[dex]
	var moves: Array[Move] = DefaultMovesets.for_species(dex)
	GameState.player_party.append(PokemonInstance.create(species, 5, moves))
	$Player.input_locked = false
```

- [ ] **Step 5 — Guard H debug key against dialog-open**

Find the existing `_debug_heal_party` / `_unhandled_input` path that handles the `H` key in `overworld_bootstrap.gd`. At the top of that handler, add a guard:

```gdscript
# If the file has something like this (find and extend it):
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		if DialogBox.is_open() or $Player.input_locked:
			return   # Phase 2d: don't heal during dialog or modal screens.
		_debug_heal_party()
		get_viewport().set_input_as_handled()
```

(If the H handler lives elsewhere or uses a different event shape, apply the same `DialogBox.is_open() or $Player.input_locked` short-circuit. The intent is: H only fires when nothing is blocking player input.)

- [ ] **Step 6 — Smoke test**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56** passing.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/Overworld.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: clean.

Manual (interactive): run the game with the Godot editor. On first boot, the StarterSelect modal appears. Arrow-navigate (left/right). Press A on any slot → modal disappears, player walks the overworld, P opens party and shows the chosen starter at L5 in slot 0.

- [ ] **Step 7 — Commit**

```bash
git add scripts/ui/starter_select.gd scenes/ui/StarterSelect.tscn \
        scripts/globals/game_state.gd scripts/overworld/overworld_bootstrap.gd
git add -A scripts/ui/*.uid scenes/ui/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): StarterSelect modal + first-boot wiring

- scenes/ui/StarterSelect.tscn + scripts/ui/starter_select.gd: modal
  CanvasLayer with three Poké Ball slots (Bulbasaur / Charmander /
  Squirtle). Arrow keys navigate, A confirms. Emits starter_chosen(dex).
- GameState loses its _debug_seed_party helper and _ready autoload hook.
  The party is now populated exclusively by StarterSelect on first boot.
- overworld_bootstrap._ready branches:
    * next_spawn set → resume from scene transition (2d.7/2d.8 path).
    * else player_party empty → await _run_starter_pick.
    * else normal start.
- H debug-heal gains a DialogBox.is_open() / input_locked short-circuit
  so it can't fire during narration or modal screens.

Consumed in 2d.7 (resume path kicks in when returning from PC interior).

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.7: PokemonCenter interior scene + Nurse heal flow

**Files:**
- Create: `scripts/overworld/pokemon_center.gd`
- Create: `scripts/overworld/nurse.gd`
- Create: `scenes/overworld/PokemonCenter.tscn`

The interior is one TextureRect background (the 240×160 PC interior image) + a handful of collision/trigger nodes. Counter + wall collision is approximated with a few StaticBody2D rectangles; Nurse is an Area2D in the "blockers" group at the cell in front of the counter; ExitMat is a Door in the "doors" group at the entry cell.

Tile layout for the 240×160 interior (in 16-px tiles, 15 wide × 10 tall):

- **Nurse cell:** (7, 2) — behind the counter, one tile above the counter top
- **ExitMat cell:** (7, 8) — red mat at the bottom-center
- **Player spawn when entering:** (7, 8) facing UP (same as ExitMat). The ExitMat only triggers on move-complete, and the spawn is an `apply_spawn` that doesn't fire move-complete, so this is safe.
- **Counter collision:** rectangle spanning x=3..11 (9 tiles wide) at y=3..4 (2 tiles tall)
- **Wall collision:** rectangles around the perimeter (top wall y=0..2, bottom wall y=9..10, left wall x=0..0, right wall x=14..14)

- [ ] **Step 1 — Create `scripts/overworld/pokemon_center.gd`**

```gdscript
extends Node2D
## Phase 2d — Pokémon Center interior scene.
##
## Structure:
##   * Background: 240×160 TextureRect with the pre-cropped PC interior image.
##   * Walls + counter: static collision rectangles.
##   * Player: inherited Player.tscn, spawned at GameState.next_spawn cell.
##   * Nurse: Area2D in "blockers" group at (7, 2), runs heal dialog on A.
##   * ExitMat: Door in "doors" group at (7, 8), returns to Overworld.

func _ready() -> void:
	$Player.apply_spawn(GameState.next_spawn)
	GameState.next_spawn = {}
	await SceneFade.fade_in()
```

- [ ] **Step 2 — Create `scripts/overworld/nurse.gd`**

```gdscript
extends Area2D
## Phase 2d — Pokémon Center nurse. Interacted with via A press.
## Runs the canonical heal sequence: dialog, pause + heal, follow-up dialog.

## Cell position on the interior map. Queried by Player._try_interact.
@export var cell: Vector2i = Vector2i(7, 2)

func _ready() -> void:
	add_to_group("blockers")

func on_interact() -> void:
	await DialogSequence.new() \
		.say("Welcome to the POKéMON CENTER!") \
		.say("We restore your POKéMON to full health.") \
		.wait(0.3) \
		.call_fn(GameState.heal_party) \
		.say("…Done! We hope to see you again!") \
		.run()
```

- [ ] **Step 3 — Create `scenes/overworld/PokemonCenter.tscn`**

Scene tree (written as text format). The Overworld .tscn has an existing `8_trainer` style; use similar id numbering.

```
[gd_scene load_steps=8 format=3 uid="uid://bphase2d004"]

[ext_resource type="Script" path="res://scripts/overworld/pokemon_center.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://scenes/overworld/Player.tscn" id="2_player"]
[ext_resource type="Texture2D" path="res://assets/maps/frlg/pc_interior.png" id="3_bg"]
[ext_resource type="Script" path="res://scripts/overworld/nurse.gd" id="4_nurse"]
[ext_resource type="Script" path="res://scripts/overworld/door.gd" id="5_door"]
[ext_resource type="PackedScene" path="res://scenes/overworld/Overworld.tscn" id="6_overworld"]

[sub_resource type="RectangleShape2D" id="shape_counter"]
size = Vector2(144, 16)

[node name="PokemonCenter" type="Node2D"]
script = ExtResource("1_script")

[node name="Background" type="TextureRect" parent="."]
texture = ExtResource("3_bg")
offset_right = 240.0
offset_bottom = 160.0

[node name="Walls" type="StaticBody2D" parent="."]

[node name="CounterShape" type="CollisionShape2D" parent="Walls"]
position = Vector2(120, 56)
shape = SubResource("shape_counter")

[node name="Player" parent="." instance=ExtResource("2_player")]
start_cell = Vector2i(7, 8)

[node name="Nurse" type="Area2D" parent="."]
script = ExtResource("4_nurse")

[node name="ExitMat" type="Area2D" parent="."]
script = ExtResource("5_door")
cell = Vector2i(7, 8)
target_scene = ExtResource("6_overworld")
```

The ExitMat's `target_cell` and `target_facing` are left at their exported defaults (0, 0, `down`) — they'll be set in 2d.8 once the PC exterior's door cell is fixed on the Overworld map.

- [ ] **Step 4 — Smoke test**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56**.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/PokemonCenter.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: clean — no "Resource not found" for the PC interior PNG, no "Script does not inherit" for door.gd or nurse.gd.

Manual (interactive): open the scene in the Godot editor, press F6. The interior renders with the nurse counter visible. Walk up to cell (7, 3) — one below the Nurse cell (7, 2) — face UP, press A. The dialog plays: "Welcome to the POKéMON CENTER!" → A to advance → "We restore your POKéMON to full health." → 0.3s pause while `heal_party()` runs → "…Done! We hope to see you again!" → A dismisses. Verify any previously-damaged party member is now at full HP via P.

- [ ] **Step 5 — Commit**

```bash
git add scenes/overworld/PokemonCenter.tscn \
        scripts/overworld/pokemon_center.gd \
        scripts/overworld/nurse.gd
git add -A scripts/overworld/*.uid scenes/overworld/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): Pokémon Center interior scene + Nurse heal flow

- scenes/overworld/PokemonCenter.tscn: 240×160 interior using the
  pre-cropped FR/LG PC map image as a single TextureRect background.
  Collision is one StaticBody2D with a rectangle over the counter
  footprint; finer wall collision can be added later if needed.
- scripts/overworld/pokemon_center.gd: _ready consumes
  GameState.next_spawn to place the player and then calls
  SceneFade.fade_in to reveal the scene.
- scripts/overworld/nurse.gd: Area2D in the "blockers" group at cell
  (7, 2). on_interact runs the canonical 3-line DialogSequence with a
  0.3s pause and GameState.heal_party() between the 2nd and 3rd lines.
- ExitMat is a Door instance at cell (7, 8) pointing back at
  Overworld.tscn. Its target_cell and target_facing are filled in in
  2d.8 once the PC exterior door cell is fixed on the overworld map.

Manual checkpoint: F6 PokemonCenter.tscn → player spawns on the mat →
walk up to the counter → press A → heal dialog plays → any damaged
party member restored.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2d.8: PC exterior on Overworld + close the door loop

**Files:**
- Modify: `scenes/overworld/Overworld.tscn`

This step places the 4×4-tile PC exterior on the overworld at a specific cell, adds a Door child at its door tile, and updates the PokemonCenter's ExitMat target_cell so the scene transitions form a proper round-trip.

**Cell layout:**
- **PC exterior top-left cell:** (4, 2) — places the building in the upper-left grassy area, well away from the path ring demo
- **Exterior footprint:** spans cells (4, 2) → (8, 5). 5 tiles wide × 4 tiles tall. At 16 px per tile that's 80×64; the sprite is 96×70 so it hangs a little over on the right + bottom edges — set the Sprite2D offset so the sprite's *footprint* aligns with the intended cells.
- **Door cell:** (6, 5) — bottom-center of the building, at the base of the door sprite
- **Overworld spawn when exiting PC:** (6, 6), facing DOWN — one cell below the door, so stepping there doesn't re-trigger entry

**ExitMat target on the interior (set in this step):** cell (6, 6), facing DOWN. The exit mat was created in 2d.7 with default target; this step fills it in via the Overworld.tscn edit on the linked ExitMat node reference… wait — actually the ExitMat is a child of `PokemonCenter.tscn`, not Overworld.tscn. We need to edit `PokemonCenter.tscn` to set its target_cell and target_facing.

- [ ] **Step 1 — Update ExitMat target in `PokemonCenter.tscn`**

Find the `[node name="ExitMat" ...]` block and add the two property lines:

```
[node name="ExitMat" type="Area2D" parent="."]
script = ExtResource("5_door")
cell = Vector2i(7, 8)
target_scene = ExtResource("6_overworld")
target_cell = Vector2i(6, 6)
target_facing = 0
```

`target_facing = 0` = `Direction.DOWN` per the Direction enum.

- [ ] **Step 2 — Add PC exterior to `Overworld.tscn`**

Open `scenes/overworld/Overworld.tscn`. Find the ext_resource block at the top and add:

```
[ext_resource type="Texture2D" path="res://assets/buildings/frlg/pc_exterior.png" id="10_pc_ext"]
[ext_resource type="PackedScene" path="res://scenes/overworld/PokemonCenter.tscn" id="11_pc_scene"]
```

Use whatever numbering is next in the file; adjust the ids (`10_*`, `11_*`) if earlier ids collide.

Then, as a child of the root node, add the `PokemonCenter` holder. Find the existing `Trainers` node and add a sibling:

```
[node name="PokemonCenter" type="Node2D" parent="."]
position = Vector2(64, 32)

[node name="Sprite" type="Sprite2D" parent="PokemonCenter"]
texture = ExtResource("10_pc_ext")
centered = false
position = Vector2(0, 0)

[node name="WallShape" type="CollisionShape2D" parent="PokemonCenter"]
position = Vector2(40, 32)

[node name="Walls" type="StaticBody2D" parent="PokemonCenter"]
position = Vector2(0, 0)
```

Positioning math: cell (4, 2) at 16 px = pixel (64, 32). The sprite is 96×70 and the building's door sits at the bottom-center — this positions the top-left of the sprite at the top-left of the cell block.

For the collision shape (one rectangle over the non-door area — door tile is at cell (6, 5), so the collision rect covers cells (4, 2)–(8, 4) for the top 3 rows plus cells (4, 5) and (7, 5)–(8, 5) for the bottom row minus the door). Simplify: cover the entire 5×4 block EXCEPT the bottom-center tile (the door). Easiest: two rectangles, one for the top 3×5 rows and two small ones flanking the door.

Cleaner: just cover all 5×4 tiles with a solid rectangle and put a Door Area2D as a *sibling* of the wall StaticBody — the Door doesn't need collision, just cell-match detection by Player._on_move_complete. But we DO want the player to stand on the door tile momentarily, which means the door tile can't be inside the solid wall rect.

Final plan: one RectangleShape2D covering the top 3 rows (60 px tall, 80 px wide) + two small rectangles on either side of the door on the bottom row (16 px tall, 32 px wide each). Then the Door Area2D at the door cell with no collision, just the Door script and its exports.

Add these sub_resources at the top of the file:

```
[sub_resource type="RectangleShape2D" id="pc_wall_top"]
size = Vector2(80, 48)

[sub_resource type="RectangleShape2D" id="pc_wall_bl"]
size = Vector2(32, 16)

[sub_resource type="RectangleShape2D" id="pc_wall_br"]
size = Vector2(32, 16)
```

And adjust the Walls node to include three CollisionShape2D children:

```
[node name="Walls" type="StaticBody2D" parent="PokemonCenter"]

[node name="Top" type="CollisionShape2D" parent="PokemonCenter/Walls"]
position = Vector2(40, 24)
shape = SubResource("pc_wall_top")

[node name="BottomLeft" type="CollisionShape2D" parent="PokemonCenter/Walls"]
position = Vector2(16, 56)
shape = SubResource("pc_wall_bl")

[node name="BottomRight" type="CollisionShape2D" parent="PokemonCenter/Walls"]
position = Vector2(64, 56)
shape = SubResource("pc_wall_br")
```

These positions are relative to the PokemonCenter node (at overworld pixel 64, 32). Top wall covers the top 3 rows. BottomLeft + BottomRight flank the door tile (door at pixel 32, 48 within PokemonCenter-local = cell (6, 5) on the overworld).

Remove the `WallShape` single-node placeholder from Step 2's first draft — replaced by the three-rect approach above.

- [ ] **Step 3 — Add the Door Area2D to `Overworld.tscn`**

As a sibling of `Walls` under `PokemonCenter`:

```
[node name="Door" type="Area2D" parent="PokemonCenter"]
script = ExtResource("12_door")
cell = Vector2i(6, 5)
target_scene = ExtResource("11_pc_scene")
target_cell = Vector2i(7, 8)
target_facing = 1
```

Also add the door script ext_resource:

```
[ext_resource type="Script" path="res://scripts/overworld/door.gd" id="12_door"]
```

`target_facing = 1` = `Direction.UP` (player faces UP after entering so they're looking toward the Nurse).
`target_cell = Vector2i(7, 8)` = the ExitMat cell on the interior, so the player spawns right back on the mat when entering.

Wait — if the player spawns ON the ExitMat cell, will the mat fire `on_enter` and immediately warp them back? The ExitMat's `on_enter` only fires from `Player._on_move_complete`. `apply_spawn` does NOT call `_on_move_complete` (it just sets `cell` + `position` directly). So spawning on the mat is safe — the mat only triggers when the player *moves onto* it, not when they're placed there.

- [ ] **Step 4 — Smoke test**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Expected: **56/56**.

Both scenes load:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/Overworld.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null

/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/wldarden/learning/pokemon-gameboy res://scenes/overworld/PokemonCenter.tscn 2>&1 | grep -E "Error|Parse" &
P=$!; sleep 3; kill $P 2>/dev/null; wait 2>/dev/null
```

Expected: both clean (no Parse Error / Invalid call / Identifier not declared).

Manual playtest sequence:
1. Launch the game. StarterSelect modal → pick a starter → overworld.
2. Navigate to cell (6, 6) — one step below the PC door. The red-roofed PC building is visible at the top-left grass area.
3. Try to walk into the side walls of the building. Player is blocked.
4. Walk up onto cell (6, 5) (the door) → screen fades to black → PokemonCenter scene loads → screen fades back in → player is standing on the ExitMat facing UP.
5. Walk up to (6, 3) (just below the Nurse) → face UP → press A → heal dialog plays.
6. After dialog, walk back down to (6, 8) → the ExitMat triggers → screen fades → Overworld reloads → player stands at (6, 6) facing DOWN. No re-entry loop.
7. Enter wild grass → damage a mon in battle → return to PC → heal via nurse → confirm party restored.

- [ ] **Step 5 — Commit**

```bash
git add scenes/overworld/Overworld.tscn scenes/overworld/PokemonCenter.tscn
git add -A scenes/overworld/*.uid 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(phase2d): PC exterior on Overworld + close the entry/exit loop

- Overworld.tscn: new PokemonCenter Node2D at pixel (64, 32) (cell 4, 2)
  containing:
    * Sprite2D rendering assets/buildings/frlg/pc_exterior.png
      (centered=false so pixel-perfect cell alignment).
    * Three-rect StaticBody2D Walls: top 3-row block + two flanks around
      the door tile (cell 6, 5). Door tile is walkable, everything else
      blocks the player.
    * Door Area2D at cell (6, 5) with target_scene = PokemonCenter.tscn,
      target_cell = (7, 8) (the ExitMat inside), target_facing = UP.
- PokemonCenter.tscn ExitMat now has target_cell = (6, 6) and
  target_facing = DOWN — closes the round-trip: stepping on the mat
  sends the player back to the overworld one tile south of the PC door
  so they don't immediately re-trigger entry.

Phase 2d is complete. All 8 sub-steps shipped; suite 56/56.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

Checklist run inline after the plan was drafted.

**Spec coverage:**

- DialogBox autoload → 2d.3 ✓
- DialogSequence builder → 2d.1 (builder state) + 2d.3 (run uses DialogBox) ✓
- SceneFade autoload → 2d.2 ✓
- GameState.next_spawn → 2d.1 ✓
- GameState.heal_party → 2d.1 ✓
- Drop debug seed → 2d.6 ✓
- NPC interaction (on_interact on blockers) → 2d.4 ✓
- Door pattern (on_enter, doors group) → 2d.4 (class) + 2d.7 (ExitMat) + 2d.8 (PC entry door) ✓
- StarterSelect modal → 2d.6 ✓
- PC exterior on Overworld → 2d.8 ✓
- PokemonCenter.tscn interior → 2d.7 ✓
- Nurse heal script → 2d.7 ✓
- Buildings extraction tool → 2d.5 ✓
- H debug guard → 2d.6 ✓
- Autoload registration in project.godot → 2d.2 + 2d.3 ✓
- 6 new GUT tests → 2d.1 ✓
- Player apply_spawn → 2d.1 ✓
- Player group membership ("player") for input-lock lookup → 2d.3 ✓

**Placeholder scan:** No `TBD`, `FIXME`, `TODO`, `fill in`, or equivalent markers. The only "later" is the intentional `TODO(pre-release)` on the H debug path from Phase 2c, which is untouched this phase.

**Type consistency:**
- `GameState.next_spawn` shape consistent across 2d.1 (definition), 2d.4 (Door sets it), 2d.6 (overworld_bootstrap consumes it), 2d.7 (PokemonCenter consumes it).
- `Player.apply_spawn` signature `Dictionary -> void` matches everywhere.
- `Door` class exports (`cell`, `target_scene`, `target_cell`, `target_facing`) used identically in 2d.7's ExitMat and 2d.8's PC Door.
- `DialogBox.queue(Array[String])` signature matches DialogSequence's `run` call.
- `Nurse.cell = (7, 2)`, `ExitMat.cell = (7, 8)`, overworld Door.cell = (6, 5) — all consistent with the interior/exterior cell math in 2d.7 and 2d.8 commentary.
- `DEX_NUMBERS: Array[int] = [1, 4, 7]` in StarterSelect ↔ `STARTER_SPECIES: Dictionary` keys 1/4/7 in overworld_bootstrap — matches.

No gaps, no stale references.
