# Phase 2c — Party of 6 + switching — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 1's hardcoded 1-vs-1 battle with full FR/LG-style teams: up to 6 Pokémon per side, voluntary and forced switching, enemy trainers with multi-Pokémon teams, participant-split XP, and a reusable PartyScreen accessible from both battle and overworld.

**Architecture:** Mirrored per-side state (`player_active_idx` / `enemy_active_idx` / `current_opponent_participants`) lives on `battle.gd` directly — no `BattleSide` wrapper, matching the project's "flat hierarchies" preference. PartyScreen is one standalone scene with three modes (SWITCH_IN_BATTLE / FORCED_SWITCH / OVERWORLD_REORDER) that both Battle and Overworld instantiate on demand. TrainerTeam becomes a declarative Resource. Pure math (XP split, party helpers) lives in small static-function modules so it's unit-testable.

**Tech Stack:** Godot 4.6 + GDScript, GUT 9 for unit tests. No new external dependencies. Current test suite: 38/38. Target: 48/48.

**Spec:** [docs/superpowers/specs/2026-04-21-phase-2c-party-switching-design.md](../specs/2026-04-21-phase-2c-party-switching-design.md)

---

## File structure

**New:**

| File | Responsibility |
|---|---|
| `scripts/battle/party_helpers.gd` | Pure static helpers: `first_non_fainted`, `all_fainted`, `can_switch_to`. No state. |
| `scripts/data/trainer_team.gd` | `TrainerTeam extends Resource` — ordered `entries` dict list + `build_instances()`. |
| `scenes/ui/PartyScreen.tscn` | Standalone CanvasLayer, 240×160 full viewport. One lead panel + stack-of-5 + submenu panel + Summary panel. |
| `scripts/ui/party_screen.gd` | `PartyScreen extends CanvasLayer` — three `Mode`s, signal API, internal navigation + swap animation. |
| `tests/unit/test_party_switching.gd` | ~10 new GUT tests. |

**Modified:**

| File | Change |
|---|---|
| `scripts/globals/game_state.gd` | Type `player_party: Array[PokemonInstance]`, add `PARTY_MAX`, add `_debug_seed_party()` called from `_ready()`. |
| `scripts/battle/xp_formula.gd` | Add `static func split_among_participants(total, count) -> int`. |
| `scripts/battle/battle.gd` | Bulk of change. New state enum values, active-idx fields, participant tracking, party-screen integration, forced-switch flow, enemy-team flow, split-XP narration. |
| `scenes/battle/Battle.tscn` | New `ActionMenu` Panel (2×2 FIGHT/POKéMON/BAG/RUN). |
| `scripts/overworld/trainer.gd` | Replace `opponent_species` + `opponent_level` with `@export var team: TrainerTeam`; rename `build_opponent()` → `build_team()`. |
| `scenes/overworld/Overworld.tscn` | Migrate `Trainer1` exports to a `TrainerTeam` sub-resource. Expanded to 3 entries in step 2c.8 for the full-team manual checkpoint. |
| `scripts/overworld/overworld_bootstrap.gd` | Pass full `GameState.player_party` and `trainer.build_team()` to `battle.start()`. Add P keybind that opens PartyScreen in OVERWORLD_REORDER mode. |

---

## Step decomposition

Eight sub-steps, each a single commit's worth of work. Steps `2c.1` and `2c.2` are pure TDD; `2c.3`–`2c.8` are integration work with GUT regression runs + manual playtest checkpoints.

1. `2c.1` — Pure math + party helpers (unit tests)
2. `2c.2` — `TrainerTeam` resource (unit tests)
3. `2c.3` — `GameState.player_party` typing + debug seed
4. `2c.4` — PartyScreen scene + OVERWORLD_REORDER mode + P keybind
5. `2c.5` — Battle ActionMenu (FIGHT/POKéMON/BAG/RUN) + state rename + RUN semantics
6. `2c.6` — PartyScreen submenu + Summary page + SWITCH_IN_BATTLE / FORCED_SWITCH modes
7. `2c.7` — Voluntary switch flow + participant tracking + XP split + bench level-up
8. `2c.8` — Forced switch + team-wipe + enemy trainer teams + expand Trainer1 to 3 mons

---

## Task 2c.1: Pure math + party helpers

**Files:**
- Create: `scripts/battle/party_helpers.gd`
- Modify: `scripts/battle/xp_formula.gd`
- Test: `tests/unit/test_party_switching.gd`

- [ ] **Step 1 — Write failing tests for `XpFormula.split_among_participants`**

Create `tests/unit/test_party_switching.gd`:

```gdscript
extends GutTest
## Phase 2c — party helpers, XP split, TrainerTeam construction.

const BULBASAUR  := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER := preload("res://data/species/004_charmander.tres")
const SQUIRTLE   := preload("res://data/species/007_squirtle.tres")
const TACKLE     := preload("res://data/moves/tackle.tres")

# ---- XpFormula.split_among_participants ----------------------------------

func test_xp_split_even() -> void:
	assert_eq(XpFormula.split_among_participants(30, 3), 10, "30/3 = 10 exact")

func test_xp_split_floors_remainder() -> void:
	# FR/LG rule: remainder is discarded, each participant gets the floor.
	assert_eq(XpFormula.split_among_participants(10, 3), 3, "10/3 floor = 3")

func test_xp_split_min_one_when_total_positive() -> void:
	# 1 XP across 3 participants would floor to 0; clamp to 1 so nobody gets
	# skipped when there's any XP to hand out.
	assert_eq(XpFormula.split_among_participants(1, 3), 1, "min-1 clamp")

func test_xp_split_zero_total_gives_zero() -> void:
	# No XP → no one gets any. The min-1 clamp only kicks in when total > 0.
	assert_eq(XpFormula.split_among_participants(0, 3), 0, "0 total → 0 each")

func test_xp_split_single_participant_full_share() -> void:
	assert_eq(XpFormula.split_among_participants(50, 1), 50, "all to sole participant")
```

- [ ] **Step 2 — Run tests, verify they fail**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 5 failures in `test_party_switching.gd` with an error like `Invalid call. Nonexistent function 'split_among_participants' in base 'GDScript'`. Other 38 tests pass.

- [ ] **Step 3 — Implement `split_among_participants`**

Append to `scripts/battle/xp_formula.gd`:

```gdscript
## Phase 2c: split XP evenly across participants. Integer floor, with a min-1
## clamp so a small grant still reaches every participant. Returns 0 when the
## input total is 0 (no phantom XP when there was nothing to give).
static func split_among_participants(total: int, count: int) -> int:
	if total <= 0 or count <= 0:
		return 0
	var each: int = total / count
	return max(1, each)
```

- [ ] **Step 4 — Run tests, verify `split_among_participants` passes**

Same command. Expected: the 5 new tests now pass (43/38 or similar as intermediate).

- [ ] **Step 5 — Write failing tests for `PartyHelpers`**

Append to `tests/unit/test_party_switching.gd`:

```gdscript
# ---- PartyHelpers --------------------------------------------------------

func _make_mon(species: Species, lvl: int = 5, hp_fraction: float = 1.0) -> PokemonInstance:
	var m := PokemonInstance.create(species, lvl, [TACKLE])
	m.current_hp = int(m.max_hp() * hp_fraction)
	return m

func _fainted(species: Species) -> PokemonInstance:
	var m := _make_mon(species, 5, 0.0)
	m.current_hp = 0
	return m

func test_first_non_fainted_picks_second_slot() -> void:
	var party := [_fainted(BULBASAUR), _make_mon(CHARMANDER), _make_mon(SQUIRTLE)]
	assert_eq(PartyHelpers.first_non_fainted(party), 1)

func test_first_non_fainted_returns_minus_one_when_all_fainted() -> void:
	var party := [_fainted(BULBASAUR), _fainted(CHARMANDER)]
	assert_eq(PartyHelpers.first_non_fainted(party), -1, "team wipe signal")

func test_all_fainted_true_on_wipe() -> void:
	var party := [_fainted(BULBASAUR), _fainted(CHARMANDER)]
	assert_true(PartyHelpers.all_fainted(party))

func test_all_fainted_false_with_alive_member() -> void:
	var party := [_fainted(BULBASAUR), _make_mon(CHARMANDER)]
	assert_false(PartyHelpers.all_fainted(party))

func test_can_switch_to_valid_slot() -> void:
	var party := [_make_mon(BULBASAUR), _make_mon(CHARMANDER), _fainted(SQUIRTLE)]
	# From active=0, slot 1 is valid (alive, non-active).
	assert_true(PartyHelpers.can_switch_to(party, 1, 0), "alive non-active slot")
	# Cannot switch to self (active slot).
	assert_false(PartyHelpers.can_switch_to(party, 0, 0), "can't switch to active")
	# Cannot switch to fainted.
	assert_false(PartyHelpers.can_switch_to(party, 2, 0), "can't switch to fainted")
```

- [ ] **Step 6 — Run tests, verify `PartyHelpers` tests fail**

Expected: 5 new failures with `Nonexistent function 'first_non_fainted' in base 'GDScript'` style errors.

- [ ] **Step 7 — Create `scripts/battle/party_helpers.gd`**

```gdscript
class_name PartyHelpers
extends RefCounted
## Phase 2c: stateless party-inspection helpers used by Battle and PartyScreen.
## Pure functions — no state, no side effects. Unit-tested in test_party_switching.

## Index of the first non-fainted Pokémon in `party`, or -1 if the whole
## party is fainted (team-wipe signal).
static func first_non_fainted(party: Array) -> int:
	for i in party.size():
		var mon = party[i]
		if mon != null and not mon.is_fainted():
			return i
	return -1

## True iff every member of `party` is fainted (or the party is empty).
static func all_fainted(party: Array) -> bool:
	for mon in party:
		if mon != null and not mon.is_fainted():
			return false
	return true

## True iff the player could legally switch to slot `idx`:
##   - slot is occupied,
##   - mon is not fainted,
##   - slot is not the current active slot (can't swap with self).
static func can_switch_to(party: Array, idx: int, active_idx: int) -> bool:
	if idx == active_idx:
		return false
	if idx < 0 or idx >= party.size():
		return false
	var mon = party[idx]
	if mon == null or mon.is_fainted():
		return false
	return true
```

- [ ] **Step 8 — Run tests, verify all pass**

Expected: all 10 new tests (5 XP + 5 PartyHelpers) pass. Suite total: 48/48 on the pure-function side already. (Integration tests for TrainerTeam come in 2c.2.)

- [ ] **Step 9 — Commit**

```bash
git add scripts/battle/party_helpers.gd scripts/battle/xp_formula.gd tests/unit/test_party_switching.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): XpFormula.split_among_participants + PartyHelpers module

- XpFormula.split_among_participants(total, count) — floor division with a
  max(1, ...) clamp when total > 0, returns 0 when total is 0. Matches FR/LG.
- PartyHelpers: stateless first_non_fainted / all_fainted / can_switch_to
  used by Battle and PartyScreen in later 2c steps.
- 10 new GUT tests for the above (XP split math + party helpers).

Suite: 48/48 on the pure-function layer. Integration + scene changes land
in 2c.2 onward.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.2: `TrainerTeam` resource

**Files:**
- Create: `scripts/data/trainer_team.gd`
- Modify: `tests/unit/test_party_switching.gd`

- [ ] **Step 1 — Write failing test**

Append to `tests/unit/test_party_switching.gd`:

```gdscript
# ---- TrainerTeam ---------------------------------------------------------

func test_trainer_team_builds_instances_with_default_moves() -> void:
	var team := TrainerTeam.new()
	team.entries = [
		{"species": BULBASAUR, "level": 5},
		{"species": CHARMANDER, "level": 7},
		{"species": SQUIRTLE, "level": 6},
	]
	var mons: Array = team.build_instances()
	assert_eq(mons.size(), 3, "3 entries → 3 instances")
	assert_eq(mons[0].species.dex_number, 1, "slot 0 = Bulbasaur")
	assert_eq(mons[0].level, 5, "slot 0 level")
	assert_eq(mons[1].species.dex_number, 4, "slot 1 = Charmander")
	assert_eq(mons[1].level, 7, "slot 1 level")
	# Empty moves → DefaultMovesets fallback (Bulbasaur's first default move is TACKLE).
	assert_gt(mons[0].moves.size(), 0, "default movesets populated")

func test_trainer_team_honors_explicit_moves() -> void:
	var team := TrainerTeam.new()
	team.entries = [
		{"species": BULBASAUR, "level": 5, "moves": [TACKLE]},
	]
	var mons: Array = team.build_instances()
	assert_eq(mons[0].moves.size(), 1, "explicit moves used verbatim")
	assert_eq(mons[0].moves[0].move, TACKLE, "TACKLE was the supplied move")
```

- [ ] **Step 2 — Run tests, verify they fail**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 2 failures, `Invalid type in 'new' expression. Base type not found: 'TrainerTeam'`.

- [ ] **Step 3 — Create `scripts/data/trainer_team.gd`**

```gdscript
class_name TrainerTeam
extends Resource
## Phase 2c: ordered team a trainer brings into battle.
##
## `entries` is an Array[Dictionary]. Each entry:
##   species: Species          required
##   level:   int              required
##   moves:   Array[Move]      optional — empty/missing means "use
##                             DefaultMovesets.for_species(species.dex_number)"
##
## Built on demand by trainer.gd / overworld_bootstrap.gd via build_instances().
## The dict-of-fields shape keeps Godot inspector editing easy; the type
## discipline lives in build_instances() rather than a per-entry class.

@export var entries: Array[Dictionary] = []

## Construct PokemonInstances for every entry, in order.
func build_instances() -> Array[PokemonInstance]:
	var out: Array[PokemonInstance] = []
	for entry in entries:
		var species: Species = entry.get("species")
		var level: int = int(entry.get("level", 1))
		if species == null:
			push_error("TrainerTeam entry has null species — skipping.")
			continue
		var moves: Array = entry.get("moves", [])
		if moves.is_empty():
			moves = DefaultMovesets.for_species(species.dex_number)
		out.append(PokemonInstance.create(species, level, moves))
	return out
```

- [ ] **Step 4 — Run tests, verify they pass**

Expected: both `TrainerTeam` tests pass. Suite now 50/38 (intermediate count).

- [ ] **Step 5 — Commit**

```bash
git add scripts/data/trainer_team.gd tests/unit/test_party_switching.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): TrainerTeam resource for declarative enemy teams

- scripts/data/trainer_team.gd: @export var entries: Array[Dictionary],
  each dict {species, level, moves?}. build_instances() resolves default
  movesets via DefaultMovesets.for_species when `moves` is empty, else
  uses the provided Move list verbatim.
- 2 new GUT tests cover default-moveset fallback and explicit-moves path.

Used by trainer.gd in 2c.5 when Trainer1 migrates off the old
opponent_species / opponent_level exports.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.3: `GameState.player_party` typing + debug seed

**Files:**
- Modify: `scripts/globals/game_state.gd`

No unit tests for this step — it's a boot-time state mutation. Verified via manual checkpoint.

- [ ] **Step 1 — Add typing + PARTY_MAX + debug seed**

Replace the contents of `scripts/globals/game_state.gd`:

```gdscript
extends Node
## Persistent game state, autoloaded as /root/GameState.
## Survives scene transitions (overworld -> battle -> overworld).

const PARTY_MAX := 6

# Player party. Typed as Array[PokemonInstance] in Phase 2c; seeded with 3
# placeholder Pokémon on boot (see _debug_seed_party). Starter selection +
# catching + Pokémon Center are separate later sub-phases.
var player_party: Array[PokemonInstance] = []

# Where the player stood on the overworld when a battle started.
var player_position: Vector2i = Vector2i.ZERO
var player_facing: int = 0

# Trainer IDs that have already been defeated.
var defeated_trainers: Dictionary = {}

# Pokédex flags.
var pokedex_seen: Dictionary = {}
var pokedex_caught: Dictionary = {}

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
	# Seed one member at mid-HP so low-HP UI can be eyeballed immediately.
	char_mon.current_hp = max(1, char_mon.max_hp() / 2)

	player_party = [bulb, char_mon, squirt]
```

- [ ] **Step 2 — Run existing tests to verify no regression**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 50/50 (or equivalent — nothing broken).

- [ ] **Step 3 — Manual checkpoint: verify seeded party**

Open Godot editor, run `scenes/overworld/Overworld.tscn` (F6). Expected:
- Overworld loads normally.
- No errors in the Output panel.
- Walk into tall grass → wild battle starts with Bulbasaur as the active mon (slot 0 of the seed) instead of whatever Phase 1 was bootstrapping.

- [ ] **Step 4 — Commit**

```bash
git add scripts/globals/game_state.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): type player_party + debug-seed 3 starters at boot

- GameState.player_party is now Array[PokemonInstance] (was untyped Array).
- const PARTY_MAX := 6.
- New _ready() hook calls _debug_seed_party() when the array is empty:
  Bulbasaur L7 (full HP), Charmander L5 (half HP so low-HP UI is eyeballable),
  Squirtle L5 (full HP).
- Marked # TODO(2d) — replaced by starter selection / catching in later
  sub-phases.

No behavior change for battle yet; subsequent steps wire GameState.player_party
(the whole array) through battle.start() and the PartyScreen.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.4: PartyScreen scene + OVERWORLD_REORDER mode + P keybind

**Files:**
- Create: `scenes/ui/PartyScreen.tscn`
- Create: `scripts/ui/party_screen.gd`
- Modify: `scripts/overworld/player.gd` (new key handler)
- Modify: `scripts/overworld/overworld_bootstrap.gd` (input lock coordination)

No unit tests this step — it's UI. Manual checkpoint exercises it.

- [ ] **Step 1 — Create `scripts/ui/party_screen.gd`**

```gdscript
class_name PartyScreen
extends CanvasLayer
## Phase 2c: reusable party screen for Battle and Overworld.
##
## Modes:
##   SWITCH_IN_BATTLE  — caller wants the player to pick a switch-in; cancel OK.
##   FORCED_SWITCH     — after active faint; cancel disabled; fainted slots un-selectable.
##   OVERWORLD_REORDER — pick two slots to swap; stays open for more swaps; B closes.
##
## The scene is single-instance: caller preloads the .tscn, instantiates,
## add_child's, connects signals, calls open(), and frees the node when done.
## Summary panel is a child toggled internally — no summary signal.

enum Mode { SWITCH_IN_BATTLE, FORCED_SWITCH, OVERWORLD_REORDER }

signal slot_chosen(idx: int)         # SWITCH_IN_BATTLE, FORCED_SWITCH
signal swap_requested(a: int, b: int)  # OVERWORLD_REORDER
signal cancelled

const SLOT_COUNT := 6
const SWAP_TWEEN_DURATION := 0.25

@onready var lead_slot: Panel = $Root/LeadSlot
@onready var slot_panels: Array[Panel] = [
	$Root/Stack/Slot1, $Root/Stack/Slot2, $Root/Stack/Slot3,
	$Root/Stack/Slot4, $Root/Stack/Slot5,
]
@onready var hint_label: Label = $Root/Hint
@onready var cursor: Panel = $Root/Cursor

var _mode: int = Mode.OVERWORLD_REORDER
var _party: Array = []
var _active_idx: int = 0
var _selected: int = 0                 # cursor position, 0 == lead
var _swap_first_pick: int = -1         # for OVERWORLD_REORDER

func open(p_party: Array, p_active_idx: int, p_mode: int) -> void:
	_party = p_party
	_active_idx = p_active_idx
	_mode = p_mode
	_selected = 0
	_swap_first_pick = -1
	_refresh_all_slots()
	_update_hint()
	_update_cursor()
	visible = true

func close() -> void:
	visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
	elif event.is_action_pressed("ui_accept"):
		_on_confirm()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel()

func _move_cursor(delta: int) -> void:
	# Cursor is linear 0..5 (lead=0, stack=1..5). Clamp to party size.
	var next: int = _selected + delta
	if next < 0 or next >= _party.size():
		return
	_selected = next
	_update_cursor()

func _on_confirm() -> void:
	if _mode == Mode.OVERWORLD_REORDER:
		if _swap_first_pick == -1:
			_swap_first_pick = _selected
			_update_hint()
		elif _swap_first_pick == _selected:
			_swap_first_pick = -1   # cancel the pending swap
			_update_hint()
		else:
			var a := _swap_first_pick
			var b := _selected
			_swap_first_pick = -1
			_animate_swap(a, b)
			swap_requested.emit(a, b)
	else:
		# SWITCH_IN_BATTLE / FORCED_SWITCH
		if not _can_select_slot(_selected):
			return
		slot_chosen.emit(_selected)

func _on_cancel() -> void:
	if _mode == Mode.FORCED_SWITCH:
		return   # disabled
	if _mode == Mode.OVERWORLD_REORDER and _swap_first_pick != -1:
		_swap_first_pick = -1     # first clear the pending pick
		_update_hint()
		return
	cancelled.emit()

func _can_select_slot(idx: int) -> bool:
	if idx < 0 or idx >= _party.size():
		return false
	var mon = _party[idx]
	if mon == null:
		return false
	if _mode == Mode.SWITCH_IN_BATTLE or _mode == Mode.FORCED_SWITCH:
		return PartyHelpers.can_switch_to(_party, idx, _active_idx)
	return true

func _refresh_all_slots() -> void:
	_refresh_slot(lead_slot, 0)
	for i in slot_panels.size():
		_refresh_slot(slot_panels[i], i + 1)

func _refresh_slot(panel: Panel, idx: int) -> void:
	if idx >= _party.size() or _party[idx] == null:
		panel.modulate = Color(0.5, 0.5, 0.5, 0.6)
		_set_slot_text(panel, "(empty)", "", 0, 0)
		return
	var mon: PokemonInstance = _party[idx]
	var label := "%s :L%d" % [mon.species.species_name, mon.level]
	var hp_text := "HP: %d/%d" % [mon.current_hp, mon.max_hp()]
	panel.modulate = Color(1, 1, 1, 0.6) if mon.is_fainted() else Color.WHITE
	_set_slot_text(panel, label, hp_text, mon.current_hp, mon.max_hp())

func _set_slot_text(panel: Panel, name_text: String, hp_text: String, hp_cur: int, hp_max: int) -> void:
	# Each slot scene has a NameLabel, HPLabel, and HPFill child.
	(panel.get_node("NameLabel") as Label).text = name_text
	(panel.get_node("HPLabel") as Label).text = hp_text
	var fill: ColorRect = panel.get_node("HPFill")
	var pct: float = 0.0 if hp_max == 0 else float(hp_cur) / float(hp_max)
	fill.size.x = fill.get_parent().size.x * pct

func _update_hint() -> void:
	match _mode:
		Mode.SWITCH_IN_BATTLE:
			hint_label.text = "Choose a POKéMON.   B: back"
		Mode.FORCED_SWITCH:
			hint_label.text = "Send out which POKéMON?"
		Mode.OVERWORLD_REORDER:
			if _swap_first_pick == -1:
				hint_label.text = "Pick first slot.   B: close"
			else:
				hint_label.text = "Pick partner (or A on same slot to cancel)."

func _update_cursor() -> void:
	var target: Panel = lead_slot if _selected == 0 else slot_panels[_selected - 1]
	cursor.position = target.position
	cursor.size = target.size
	cursor.visible = true

func _animate_swap(a: int, b: int) -> void:
	# Cosmetic: tween the two panels' positions so the player sees them swap,
	# then refresh the slot contents against the newly-swapped _party.
	var panel_a := _panel_for_idx(a)
	var panel_b := _panel_for_idx(b)
	var pos_a := panel_a.position
	var pos_b := panel_b.position
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel_a, "position", pos_b, SWAP_TWEEN_DURATION)
	tw.tween_property(panel_b, "position", pos_a, SWAP_TWEEN_DURATION)
	await tw.finished
	# Restore panels to their original positions, then redraw the new contents
	# (the _party array was swapped by the caller via swap_requested).
	panel_a.position = pos_a
	panel_b.position = pos_b
	_refresh_all_slots()
	_update_cursor()

func _panel_for_idx(idx: int) -> Panel:
	return lead_slot if idx == 0 else slot_panels[idx - 1]
```

- [ ] **Step 2 — Create `scenes/ui/PartyScreen.tscn`**

Create via the Godot editor (the .tscn format is verbose; see layout spec). The scene tree should be:

```
PartyScreen (CanvasLayer, layer=10, script=party_screen.gd)
└ Root (Control, 0,0 → 240,160, sky-blue background ColorRect behind everything)
  ├ Background (ColorRect full-rect, color=#98d8f0)
  ├ Title (Label "POKéMON" at (8,6), Kenney Mini bold)
  ├ LeadSlot (Panel at (8,28) sized 96×68 with peach styling)
  │  ├ NameLabel (Label, local pos)
  │  ├ HPLabel (Label)
  │  └ HPFill (ColorRect over an HPBarBG, classic green→yellow→red via modulate)
  ├ Stack (Control at (108,28) 124×120)
  │  ├ Slot1 (Panel 124×22) through Slot5 (Panel) — each with NameLabel, HPLabel, HPFill
  ├ Hint (Label at (8, 146) full-width)
  └ Cursor (Panel 1-px outline, drawn last so it overlays)
```

Save as `scenes/ui/PartyScreen.tscn` with uid auto-assigned.

Smoke-test by running the scene directly (F6 on the tscn in the editor). Expected: scene loads, no script errors, no slots populated (because `open()` hasn't been called — visible is false by default in a fresh instance, override to true in editor for quick visual test).

- [ ] **Step 3 — Wire P keybind + input lock in overworld**

In `scripts/overworld/player.gd`, extend `_process` or add input handling in a new `_unhandled_input` to detect a P press (define a custom InputMap action `"open_party"` bound to Key P):

Add to the top of `scripts/overworld/player.gd` near the other exports:

```gdscript
signal party_screen_requested
```

Inside `_process`, before any early returns:

```gdscript
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("open_party") and not input_locked and not is_moving:
		party_screen_requested.emit()
		return
	# ... existing body unchanged ...
```

Add the InputMap action to the project: open the Godot editor → Project → Project Settings → Input Map → add action `open_party`, bind to Key P. Save project settings.

In `scripts/overworld/overworld_bootstrap.gd` add a handler. Near the top of the file's script-body (after the existing field declarations), add:

```gdscript
const PARTY_SCREEN := preload("res://scenes/ui/PartyScreen.tscn")
var _party_screen: PartyScreen = null
```

In `_ready()` (or the existing setup hook where other signals get connected), add:

```gdscript
$Player.party_screen_requested.connect(_on_party_screen_requested)
```

Add these handlers at the bottom of the file:

```gdscript
func _on_party_screen_requested() -> void:
	if _party_screen != null:
		return
	_party_screen = PARTY_SCREEN.instantiate()
	add_child(_party_screen)
	_party_screen.swap_requested.connect(_on_party_swap)
	_party_screen.cancelled.connect(_on_party_closed)
	$Player.input_locked = true
	_party_screen.open(GameState.player_party, 0, PartyScreen.Mode.OVERWORLD_REORDER)

func _on_party_swap(a: int, b: int) -> void:
	var tmp = GameState.player_party[a]
	GameState.player_party[a] = GameState.player_party[b]
	GameState.player_party[b] = tmp
	# PartyScreen's own animation is already playing; the swap in GameState
	# is instantaneous. Next open() reads from the post-swap state.

func _on_party_closed() -> void:
	if _party_screen == null:
		return
	_party_screen.queue_free()
	_party_screen = null
	$Player.input_locked = false
```

- [ ] **Step 4 — Manual checkpoint**

Run Overworld (F6). Expected:
- Walk around normally with arrow keys.
- Press **P** → PartyScreen opens showing 3 seeded mons (Bulbasaur lead, Charmander at half HP, Squirtle).
- Arrow up/down moves a cursor outline between the lead slot and stack slots.
- Press A on slot 0, then A on slot 1 → slot panels tween to each other's positions; after tween ends, Bulbasaur shows in stack row 1, Charmander in lead.
- Press B with no pending pick → PartyScreen closes, player walks again.
- Press P again → slot order is Charmander (lead), Bulbasaur (slot 1), Squirtle (slot 2) — persists across opens.

- [ ] **Step 5 — Run tests (regression)**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: still 50/50 (no tests added this step; no regression).

- [ ] **Step 6 — Commit**

```bash
git add scenes/ui/PartyScreen.tscn scripts/ui/party_screen.gd \
        scripts/overworld/player.gd scripts/overworld/overworld_bootstrap.gd \
        project.godot
git commit -m "$(cat <<'EOF'
feat(phase2c): PartyScreen scene + overworld reorder + P keybind

- scenes/ui/PartyScreen.tscn + scripts/ui/party_screen.gd: standalone
  CanvasLayer with three Modes (SWITCH_IN_BATTLE, FORCED_SWITCH,
  OVERWORLD_REORDER). Lead slot on left, 5-tall stack on right, cursor
  outline, hint label. Swap animation tweens two slot panels over 0.25s.
- Player.party_screen_requested signal fired on 'open_party' input action
  (Key P, added to InputMap).
- overworld_bootstrap instantiates PartyScreen on request, connects
  swap/cancelled signals, locks Player.input_locked during display.
  Swap handler mutates GameState.player_party in place so the new
  order persists into subsequent battles.

Manual checkpoint: 3 seeded starters render; arrows navigate; A-A swaps
two slots with animation; B closes; P reopens with new order.

Battle-side modes (SWITCH_IN_BATTLE / FORCED_SWITCH) and the submenu /
Summary view are wired up in 2c.6.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.5: Battle ActionMenu + state rename + RUN semantics

**Files:**
- Modify: `scenes/battle/Battle.tscn` (add ActionMenu Panel)
- Modify: `scripts/battle/battle.gd` (state enum, new menu handling, RUN)
- Modify: `scripts/battle/battle_result.gd` (no code change; just verify ESCAPED is acceptable)

No unit tests — integration behavior. Manual checkpoint covers it.

- [ ] **Step 1 — Add ActionMenu Panel to `Battle.tscn`**

In the Godot editor, open `scenes/battle/Battle.tscn`. Duplicate the existing `MoveMenu` Panel (it's 112×40 in the bottom-right), rename the copy to `ActionMenu`, and lay it out identically. Replace its 4 children `Move1..Move4` with `Fight`, `Pokemon`, `Bag`, `Run` (same positions as the 2×2 move grid). Each has a `Label` child:

- `Fight/Label.text = "FIGHT"`
- `Pokemon/Label.text = "POKéMON"`
- `Bag/Label.text = "BAG"`
- `Run/Label.text = "RUN"`

Colour `Bag/Label.modulate = Color(0.5, 0.5, 0.5)` to grey-out the unusable entry. Set the whole `ActionMenu.visible = false` in the editor. Save.

- [ ] **Step 2 — Extend state enum + references in `battle.gd`**

In `scripts/battle/battle.gd`, replace the enum declaration:

```gdscript
enum State {
	BOOTING,
	ACTION_MENU,     # top-level FIGHT / POKéMON / BAG / RUN
	MOVE_MENU,       # the existing 2×2 move grid (was CHOOSE_ACTION)
	PARTY_MENU,      # PartyScreen is open
	SWITCHING_IN,    # "Come back / Go" narration
	FAINT_SWITCH,    # forced-switch PartyScreen after active KO
	RESOLVING,
	ENDED,
}
```

Find and replace every `State.CHOOSE_ACTION` with `State.MOVE_MENU` (search-and-replace the symbol — there should be ~4 sites in battle.gd).

- [ ] **Step 3 — Add ActionMenu refs + navigation**

Near the other `@onready` declarations, add:

```gdscript
@onready var action_menu: Panel = $ActionMenu
@onready var action_buttons: Array[Panel] = [
	$ActionMenu/Fight, $ActionMenu/Pokemon,
	$ActionMenu/Bag, $ActionMenu/Run,
]

const ACTION_FIGHT := 0
const ACTION_POKEMON := 1
const ACTION_BAG := 2
const ACTION_RUN := 3

var selected_action_idx: int = 0
```

In `_ready()`, add after the existing `move_menu.visible = false`:

```gdscript
action_menu.visible = false
```

- [ ] **Step 4 — Replace `_enter_choose_action` entry flow with `_enter_action_menu`**

Find the existing `_enter_choose_action()` function. Rename it and rewire:

```gdscript
func _enter_action_menu() -> void:
	state = State.ACTION_MENU
	_refresh_labels()
	_set_dialog("What will %s do?" % player_mon.species.species_name)
	action_menu.visible = true
	move_menu.visible = false
	selected_action_idx = 0
	_update_action_cursor()

func _enter_move_menu() -> void:
	state = State.MOVE_MENU
	action_menu.visible = false
	move_menu.visible = true
	_clamp_cursor()
	_update_cursor_position()
```

Every site that previously called `_enter_choose_action()` now calls `_enter_action_menu()` instead. (At the end of `start()`, inside `_resolve_turn` non-faint branch, and inside `_handle_faint` after the level-up loop — search for the old name to find them all.)

- [ ] **Step 5 — Handle input while in ACTION_MENU**

Update `_process`:

```gdscript
func _process(_delta: float) -> void:
	match state:
		State.ACTION_MENU:
			_handle_action_menu_input()
		State.MOVE_MENU:
			_handle_menu_input()
```

Add the handler:

```gdscript
func _handle_action_menu_input() -> void:
	var changed := false
	if Input.is_action_just_pressed("ui_right") and selected_action_idx % 2 == 0:
		selected_action_idx += 1
		changed = true
	elif Input.is_action_just_pressed("ui_left") and selected_action_idx % 2 == 1:
		selected_action_idx -= 1
		changed = true
	elif Input.is_action_just_pressed("ui_down") and selected_action_idx < 2:
		selected_action_idx += 2
		changed = true
	elif Input.is_action_just_pressed("ui_up") and selected_action_idx >= 2:
		selected_action_idx -= 2
		changed = true
	elif Input.is_action_just_pressed("ui_accept"):
		_submit_action(selected_action_idx)
		return

	if changed:
		_update_action_cursor()

func _update_action_cursor() -> void:
	cursor.visible = true
	var btn: Panel = action_buttons[selected_action_idx]
	cursor.position = btn.position + Vector2(-2, -2)
	cursor.size = btn.size + Vector2(4, 4)

func _submit_action(idx: int) -> void:
	match idx:
		ACTION_FIGHT:
			_enter_move_menu()
		ACTION_POKEMON:
			# Wired in 2c.7 — stub for now so it's non-destructive.
			_set_dialog("(POKéMON menu — wired in 2c.7)")
		ACTION_BAG:
			# Greyed out — Phase 3+.
			_set_dialog("The BAG is empty…")
		ACTION_RUN:
			_try_run()
```

- [ ] **Step 6 — Implement RUN**

Append:

```gdscript
func _try_run() -> void:
	if context.is_trainer:
		await _print_dialog("No! There's no running from a trainer battle!")
		_enter_action_menu()
		return
	await _print_dialog("Got away safely!")
	state = State.ENDED
	var result := BattleResult.new()
	result.outcome = BattleResult.Outcome.ESCAPED
	battle_ended.emit(result)
```

- [ ] **Step 7 — Run regression tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 50/50 — no test changes, no regressions.

- [ ] **Step 8 — Manual checkpoint**

F5 overworld, walk into tall grass until a wild battle starts. Expected:
- Battle opens with the action menu (not the move grid).
- `FIGHT` selected by cursor; arrow keys move cursor through 2×2.
- `FIGHT` → enter → existing move grid appears, unchanged.
- Return to action menu (win a battle; on next battle), select `BAG` → dialog "The BAG is empty…" and menu stays (pressing accept again re-fires).
- Select `RUN` → "Got away safely!" → back to overworld, no defeat narration.
- Start a trainer battle → select `RUN` → "No! There's no running from a trainer battle!" → return to action menu.
- Select `POKéMON` → stub dialog "(POKéMON menu — wired in 2c.7)". Harmless no-op.

- [ ] **Step 9 — Commit**

```bash
git add scenes/battle/Battle.tscn scripts/battle/battle.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): battle top-level ActionMenu (FIGHT/POKéMON/BAG/RUN)

- Battle.tscn: new ActionMenu Panel (same 112×40 footprint as MoveMenu,
  rendered in the same spot). 2x2 cells, BAG label greyed via modulate.
- battle.gd state enum: CHOOSE_ACTION renamed to MOVE_MENU; new values
  ACTION_MENU, PARTY_MENU, SWITCHING_IN, FAINT_SWITCH (the latter two
  plumbed in in 2c.6/2c.7/2c.8).
- _enter_action_menu() replaces _enter_choose_action() as the battle's
  return-to-input state. _enter_move_menu() opens the existing move grid.
- RUN works in wild battles (emits BattleResult with Outcome.ESCAPED);
  disabled in trainer battles with "No! There's no running…" narration.
- BAG shows placeholder "The BAG is empty…" dialog (greyed until Phase 3).
- POKéMON is a stub dialog pending 2c.7 (voluntary switch wiring).

Manual: F5 → wild battle → action menu appears, FIGHT works as before,
RUN escapes, BAG is inert, POKéMON stubs.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.6: PartyScreen submenu + Summary + battle modes

**Files:**
- Modify: `scenes/ui/PartyScreen.tscn` (submenu Panel + Summary Panel children)
- Modify: `scripts/ui/party_screen.gd` (submenu + Summary state machine)

- [ ] **Step 1 — Add Submenu Panel to PartyScreen.tscn**

In the editor, add a `Submenu` Panel child of `Root`, positioned at (140, 88) sized 92×56, initially invisible. Three Label children stacked: `SummaryLabel` ("SUMMARY"), `SwitchLabel` ("SWITCH"), `CancelLabel` ("CANCEL"). Add a `SubmenuCursor` Panel outline sibling.

Add a `Summary` Panel child of `Root`, full-viewport (240×160), initially invisible, with:

- `Title` Label (top-left, "{NAME} :L{LEVEL}" set at runtime)
- `ExpLine` Label (below title: "EXP 145  To next: 27")
- `StatsGrid` VBoxContainer with 6 labels (HP/ATK/DEF/SPA/SPD/SPE — filled at runtime)
- `TypeLine` Label
- `MovesList` VBoxContainer with 4 Labels (move names)

- [ ] **Step 2 — Add submenu + summary state machine to `party_screen.gd`**

Extend the PartyScreen script. Add near the enum:

```gdscript
enum SubmenuAction { SUMMARY, SWITCH, CANCEL }
enum View { LIST, SUBMENU, SUMMARY }

var _view: int = View.LIST
var _submenu_idx: int = 0
```

Add `@onready` refs:

```gdscript
@onready var submenu: Panel = $Root/Submenu
@onready var submenu_labels: Array[Label] = [
	$Root/Submenu/SummaryLabel,
	$Root/Submenu/SwitchLabel,
	$Root/Submenu/CancelLabel,
]
@onready var submenu_cursor: Panel = $Root/Submenu/SubmenuCursor
@onready var summary_panel: Panel = $Root/Summary
@onready var summary_title: Label = $Root/Summary/Title
@onready var summary_exp: Label = $Root/Summary/ExpLine
@onready var summary_stat_labels: Array[Label] = [
	$Root/Summary/StatsGrid/HP, $Root/Summary/StatsGrid/ATK,
	$Root/Summary/StatsGrid/DEF, $Root/Summary/StatsGrid/SPA,
	$Root/Summary/StatsGrid/SPD, $Root/Summary/StatsGrid/SPE,
]
@onready var summary_type: Label = $Root/Summary/TypeLine
@onready var summary_moves: Array[Label] = [
	$Root/Summary/MovesList/Move1, $Root/Summary/MovesList/Move2,
	$Root/Summary/MovesList/Move3, $Root/Summary/MovesList/Move4,
]
```

Rework `_input()` as a dispatcher:

```gdscript
func _input(event: InputEvent) -> void:
	if not visible:
		return
	match _view:
		View.LIST:
			_handle_list_input(event)
		View.SUBMENU:
			_handle_submenu_input(event)
		View.SUMMARY:
			_handle_summary_input(event)

func _handle_list_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
	elif event.is_action_pressed("ui_accept"):
		_on_list_confirm()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel()

func _on_list_confirm() -> void:
	if _mode == Mode.OVERWORLD_REORDER:
		_on_confirm()   # delegates to the existing swap-pick flow
		return
	# SWITCH_IN_BATTLE / FORCED_SWITCH — open the submenu on the selected slot.
	if _selected >= _party.size() or _party[_selected] == null:
		return
	_view = View.SUBMENU
	submenu.visible = true
	_submenu_idx = 0
	_update_submenu_cursor()

func _handle_submenu_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_submenu_idx = max(0, _submenu_idx - 1)
		_update_submenu_cursor()
	elif event.is_action_pressed("ui_down"):
		_submenu_idx = min(_submenu_options().size() - 1, _submenu_idx + 1)
		_update_submenu_cursor()
	elif event.is_action_pressed("ui_accept"):
		_on_submenu_confirm()
	elif event.is_action_pressed("ui_cancel"):
		_close_submenu()

func _on_submenu_confirm() -> void:
	var action: int = _submenu_options()[_submenu_idx]
	match action:
		SubmenuAction.SUMMARY:
			_show_summary(_selected)
		SubmenuAction.SWITCH:
			if not _can_select_slot(_selected):
				return
			_close_submenu()
			slot_chosen.emit(_selected)
		SubmenuAction.CANCEL:
			_close_submenu()

func _submenu_options() -> Array:
	# Active slot in SWITCH_IN_BATTLE: omit SWITCH (can't switch to self).
	# FORCED_SWITCH: omit CANCEL.
	var opts := []
	opts.append(SubmenuAction.SUMMARY)
	if _mode != Mode.FORCED_SWITCH or _can_select_slot(_selected):
		if _selected != _active_idx and _can_select_slot(_selected):
			opts.append(SubmenuAction.SWITCH)
	if _mode != Mode.FORCED_SWITCH:
		opts.append(SubmenuAction.CANCEL)
	return opts

func _update_submenu_cursor() -> void:
	var opts := _submenu_options()
	# Hide rows that aren't in opts. Map opts → visible labels in order.
	for i in submenu_labels.size():
		submenu_labels[i].visible = (i < opts.size())
		if i < opts.size():
			submenu_labels[i].text = _submenu_label_text(opts[i])
	var target: Label = submenu_labels[_submenu_idx]
	submenu_cursor.position = target.position
	submenu_cursor.size = target.size

func _submenu_label_text(action: int) -> String:
	match action:
		SubmenuAction.SUMMARY: return "SUMMARY"
		SubmenuAction.SWITCH:  return "SWITCH"
		SubmenuAction.CANCEL:  return "CANCEL"
	return "?"

func _close_submenu() -> void:
	submenu.visible = false
	_view = View.LIST

func _show_summary(idx: int) -> void:
	var mon: PokemonInstance = _party[idx]
	if mon == null:
		return
	_view = View.SUMMARY
	summary_title.text = "%s :L%d" % [mon.species.species_name, mon.level]
	summary_exp.text = "EXP %d  To next: %d" % [mon.experience, mon.exp_to_next_level()]
	var stats: Array = [
		"HP:  %d/%d" % [mon.current_hp, mon.max_hp()],
		"ATK: %d" % mon.stat(Enums.StatKey.ATTACK),
		"DEF: %d" % mon.stat(Enums.StatKey.DEFENSE),
		"SPA: %d" % mon.stat(Enums.StatKey.SP_ATTACK),
		"SPD: %d" % mon.stat(Enums.StatKey.SP_DEFENSE),
		"SPE: %d" % mon.stat(Enums.StatKey.SPEED),
	]
	for i in summary_stat_labels.size():
		summary_stat_labels[i].text = stats[i]
	var type_names: Array = []
	for t in mon.type_list():
		type_names.append(Enums.type_name(t).to_upper())
	summary_type.text = "TYPE: " + "/".join(type_names)
	for i in summary_moves.size():
		if i < mon.moves.size():
			summary_moves[i].text = mon.moves[i].move.move_name
		else:
			summary_moves[i].text = "—"
	summary_panel.visible = true

func _handle_summary_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		summary_panel.visible = false
		_view = View.SUBMENU   # return to submenu over the slot we came from
```

Remove the now-duplicate `_on_confirm` and `_on_cancel` bodies that previously handled the LIST state directly — they're called by `_handle_list_input`. Keep the existing `_on_confirm` for OVERWORLD_REORDER's swap-pick logic; it's still invoked via the delegation line in `_on_list_confirm`.

- [ ] **Step 3 — Verify Enums helper `type_name(int) -> String` exists**

```bash
grep -n "type_name" scripts/data/enums.gd
```

If missing, add it:

```gdscript
static func type_name(t: int) -> String:
	return Type.keys()[t].to_lower() if t >= 0 and t < Type.size() else "???"
```

If the enum name differs (e.g. `NONE = 0, NORMAL = 1, ...`), adjust accordingly so `type_name(Enums.Type.GRASS)` returns `"grass"`.

- [ ] **Step 4 — Manual checkpoint (overworld only, battle wiring comes in 2c.7)**

Run overworld, press P, arrow to any slot, press A. Expected:
- Submenu appears to the right of the slot with `SUMMARY / SWITCH / CANCEL`.
- Down arrow cycles through entries.
- `SUMMARY` → full-viewport Summary page with stats + moves renders. B closes back to submenu.
- `SWITCH` on a valid slot — nothing happens yet in overworld mode (PartyScreen emits `slot_chosen`, but the overworld handler doesn't consume it for reorder). This is OK — we'll short-circuit: in OVERWORLD_REORDER, `_on_submenu_confirm`'s SWITCH branch should defer to the existing swap-pick flow. To keep behavior clean:

Adjust `_on_submenu_confirm` SWITCH branch:

```gdscript
SubmenuAction.SWITCH:
	if _mode == Mode.OVERWORLD_REORDER:
		_close_submenu()
		_on_confirm()    # falls back into the overworld swap-pick logic
	else:
		if not _can_select_slot(_selected):
			return
		_close_submenu()
		slot_chosen.emit(_selected)
```

Re-run manual checkpoint — SWITCH in overworld now triggers the pick/swap flow (picks first slot, highlight updates, navigate to second slot, A again swaps).

- [ ] **Step 5 — Run regression tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 50/50, no regressions.

- [ ] **Step 6 — Commit**

```bash
git add scenes/ui/PartyScreen.tscn scripts/ui/party_screen.gd scripts/data/enums.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): PartyScreen submenu + 1-page Summary view

- PartyScreen gains SUBMENU and SUMMARY internal views on top of the
  existing LIST view, dispatched by _view state machine.
- Submenu (SUMMARY / SWITCH / CANCEL) opens when A is pressed on a slot
  in SWITCH_IN_BATTLE and FORCED_SWITCH modes. In OVERWORLD_REORDER,
  SWITCH routes through the existing swap-pick flow. FORCED_SWITCH
  omits CANCEL; selecting the active slot in SWITCH_IN_BATTLE omits
  SWITCH (can't switch to self).
- Summary: 1-page, full-viewport — name+level header, EXP/to-next,
  6 stats + type + 4 moves. B or A closes back to the submenu.
- Enums.type_name(int) helper added (or verified) for the type line.

Battle-side opens of the PartyScreen (voluntary switch / forced switch)
are wired in 2c.7 and 2c.8.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.7: Voluntary switch + participant tracking + XP split + bench level-up

**Files:**
- Modify: `scripts/battle/battle.gd`

- [ ] **Step 1 — Add active-idx + participant state**

Near the existing `var player_mon` declaration:

```gdscript
var player_active_idx: int = 0
var enemy_active_idx: int = 0
var current_opponent_participants: Array[int] = []   # indices into player_party
```

Replace the body of `start()`:

```gdscript
func start(p_player: Array, p_enemy: Array, p_context: BattleContext) -> void:
	player_party = p_player
	enemy_party = p_enemy
	context = p_context
	player_active_idx = PartyHelpers.first_non_fainted(player_party)
	enemy_active_idx = PartyHelpers.first_non_fainted(enemy_party)
	if player_active_idx < 0 or enemy_active_idx < 0:
		push_error("Battle.start: a side has no usable Pokémon.")
		return
	player_mon = player_party[player_active_idx]
	enemy_mon = enemy_party[enemy_active_idx]
	current_opponent_participants = [player_active_idx]

	_apply_sprites()
	_refresh_hp_bars(true)
	_refresh_labels()
	_refresh_move_menu()

	enemy_hp_bg.visible = true
	player_hp_bg.visible = true
	dialog_box.visible = true

	_enter_action_menu()
```

- [ ] **Step 2 — Wire POKéMON → PartyScreen**

Add preload near the top of `battle.gd`:

```gdscript
const PARTY_SCREEN := preload("res://scenes/ui/PartyScreen.tscn")
var _party_screen: PartyScreen = null
```

Replace the `ACTION_POKEMON` match arm inside `_submit_action`:

```gdscript
ACTION_POKEMON:
	_open_party_screen_switch()
```

Add the helpers:

```gdscript
func _open_party_screen_switch() -> void:
	state = State.PARTY_MENU
	action_menu.visible = false
	_party_screen = PARTY_SCREEN.instantiate()
	add_child(_party_screen)
	_party_screen.slot_chosen.connect(_on_party_slot_chosen_voluntary)
	_party_screen.cancelled.connect(_on_party_cancelled_voluntary)
	_party_screen.open(player_party, player_active_idx, PartyScreen.Mode.SWITCH_IN_BATTLE)

func _on_party_slot_chosen_voluntary(idx: int) -> void:
	_close_party_screen()
	await _switch_to(idx, false)
	# Switch spent the turn — enemy attacks.
	var enemy_move: Move = _choose_enemy_move()
	_resolve_enemy_only_turn(enemy_move)

func _on_party_cancelled_voluntary() -> void:
	_close_party_screen()
	_enter_action_menu()

func _close_party_screen() -> void:
	if _party_screen != null:
		_party_screen.queue_free()
		_party_screen = null
```

- [ ] **Step 3 — Implement `_switch_to`**

```gdscript
func _switch_to(idx: int, is_forced: bool) -> void:
	state = State.SWITCHING_IN
	if not is_forced:
		await _print_dialog("Come back, %s!" % player_mon.species.species_name)
	player_active_idx = idx
	player_mon = player_party[idx]
	if not current_opponent_participants.has(idx):
		current_opponent_participants.append(idx)
	_apply_sprites()
	_refresh_hp_bars(true)
	_refresh_labels()
	_refresh_move_menu()
	await _print_dialog("Go, %s!" % player_mon.species.species_name)
```

- [ ] **Step 4 — `_resolve_enemy_only_turn` (enemy attacks after a voluntary switch)**

Split `_resolve_turn` so the voluntary-switch case can reuse the enemy-attack half without pretending the player picked a move. Add:

```gdscript
func _resolve_enemy_only_turn(enemy_move: Move) -> void:
	state = State.RESOLVING
	await _execute_attack(enemy_mon, player_mon, enemy_move)
	if player_mon.is_fainted():
		await _handle_faint(player_mon)
		return
	_enter_action_menu()
```

- [ ] **Step 5 — Compute participant XP split + apply bench level-ups**

Add:

```gdscript
## Returns {participant_idx: xp_share} for the current enemy's KO.
func _compute_participant_xp_split(total: int) -> Dictionary:
	var out := {}
	var participants := current_opponent_participants
	if participants.is_empty():
		participants = [player_active_idx]   # defensive: always at least the active.
	var each: int = XpFormula.split_among_participants(total, participants.size())
	for idx in participants:
		out[idx] = each
	return out

## Silently apply each LevelUpEvent for a benched participant: stats already
## updated by gain_exp(); auto-learn new moves if a slot is free; skip
## (no replace prompt) if the mon already knows 4 moves.
func _apply_bench_levelups(mon: PokemonInstance, events: Array[LevelUpEvent]) -> void:
	for event in events:
		var new_moves: Array[Move] = LearnsetResolver.moves_learned_at(
			mon.species, event.new_level
		)
		for move in new_moves:
			if LearnsetResolver.already_knows(mon, move):
				continue
			if mon.moves.size() < 4:
				mon.moves.append(MoveSlot.from_move(move))
			# else: skip silently.
```

- [ ] **Step 6 — Rewire `_handle_faint` to distribute split XP**

Replace the enemy-faint branch inside `_handle_faint`. Full updated function:

```gdscript
func _handle_faint(mon: PokemonInstance) -> void:
	await _print_dialog("%s fainted!" % mon.species.species_name)

	if mon == enemy_mon:
		var total_xp: int = _compute_xp_for_opponent(enemy_mon)
		var splits: Dictionary = _compute_participant_xp_split(total_xp)
		for idx in splits.keys():
			var amount: int = splits[idx]
			var p_mon: PokemonInstance = player_party[idx]
			await _print_dialog("%s gained %d EXP!" % [p_mon.species.species_name, amount])
			var events: Array[LevelUpEvent] = p_mon.gain_exp(amount)
			if events.is_empty():
				continue
			if p_mon == player_mon:
				_refresh_hp_bars(false)
				_refresh_labels()
				for event in events:
					await _show_level_up_screens(event)
					var learned: Array[Move] = LearnsetResolver.moves_learned_at(
						p_mon.species, event.new_level
					)
					for move in learned:
						if LearnsetResolver.already_knows(p_mon, move):
							continue
						await _try_learn_move(p_mon, move)
			else:
				_apply_bench_levelups(p_mon, events)

		# Team-wipe / next-enemy handling lands in 2c.8. For 2c.7 we still
		# assume a single-mon enemy party, so the old "emit WIN" behavior
		# holds.
		state = State.ENDED
		var result := BattleResult.new()
		result.outcome = BattleResult.Outcome.WIN
		result.xp_gained = total_xp
		battle_ended.emit(result)
	else:
		# Player-side faint. 2c.8 wires the forced-switch flow; 2c.7 still
		# ends the battle as LOSE on any player faint to keep this step's
		# diff surface small.
		state = State.ENDED
		var result := BattleResult.new()
		result.outcome = BattleResult.Outcome.LOSE
		await _print_dialog("You are out of usable Pokémon!")
		battle_ended.emit(result)
```

- [ ] **Step 7 — Run regression tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 50/50, no regressions.

- [ ] **Step 8 — Manual checkpoints**

Run Overworld (F5):

1. **Voluntary switch, no faint** — Start a wild battle with the default party. On action menu, pick POKéMON → PartyScreen opens. Pick Charmander slot → submenu → SWITCH → "Come back Bulbasaur / Go Charmander!" → enemy attacks → Charmander takes damage → action menu reopens. Continue, win the battle.
2. **Participant XP split** — Win a wild battle you voluntarily switched during. Dialogs read, e.g., "Bulbasaur gained 12 EXP!" then "Charmander gained 12 EXP!" (for a 24-XP kill split across two participants). Only the active mon shows the level-up screens when crossing; the benched one levels silently.
3. **Regression: straight fight path** — Start a fresh wild battle, pick FIGHT without switching → exactly the pre-2c behavior, XP goes to a single participant (the only active mon).

- [ ] **Step 9 — Commit**

```bash
git add scripts/battle/battle.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): voluntary switching + XP split across participants

- battle.gd: player_active_idx / enemy_active_idx / current_opponent_participants
  fields. Start() resolves active slots via PartyHelpers.first_non_fainted
  and initializes the participant set to [player_active_idx].
- POKéMON action in the top menu opens PartyScreen in SWITCH_IN_BATTLE
  mode. Slot selection awaits _switch_to(idx, is_forced=false) which
  narrates Come-back / Go, updates the active index + sprite + HUD, and
  adds the new active to the participant set.
- Voluntary switch costs the turn: _resolve_enemy_only_turn fires the
  enemy's move without a player attack, then returns to ACTION_MENU.
- _compute_participant_xp_split splits XP via XpFormula.split_among_participants
  and returns a {idx: amount} dict. _handle_faint iterates it, narrating
  each participant's gain, applying level-up screens for the currently
  active mon and silent bench level-ups (+ auto-learn, no replace prompt)
  for everyone else.
- Single-mon enemy team assumed in this step. Forced-switch on player
  faint + multi-mon enemy teams land in 2c.8.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2c.8: Forced switch + team wipe + enemy trainer teams

**Files:**
- Modify: `scripts/battle/battle.gd`
- Modify: `scripts/overworld/trainer.gd`
- Modify: `scenes/overworld/Overworld.tscn` (Trainer1 migration)
- Modify: `scripts/overworld/overworld_bootstrap.gd` (pass full team)

- [ ] **Step 1 — Migrate `trainer.gd` to `TrainerTeam`**

Replace the exports + `build_opponent` in `scripts/overworld/trainer.gd`:

```gdscript
@export var team: TrainerTeam
```

Remove:
```gdscript
@export var opponent_species: Species
@export_range(1, 100) var opponent_level: int = 5
```

Replace `build_opponent`:

```gdscript
## Phase 2c: build the full team, not just one Pokémon.
func build_team() -> Array[PokemonInstance]:
	if team == null or team.entries.is_empty():
		push_error("Trainer %s has no team configured." % trainer_id)
		return []
	return team.build_instances()
```

Remove `build_opponent()`.

- [ ] **Step 2 — Migrate `Trainer1` in `Overworld.tscn`**

Open `scenes/overworld/Overworld.tscn` in the editor. On the Trainer1 node:
- Delete `opponent_species` + `opponent_level` from the export values.
- Add `team` → New Resource → `TrainerTeam`.
- Inside the new TrainerTeam, add 3 entries to `entries`:

```
entries = [
	{ "species": <Charmander>, "level": 5 },
	{ "species": <Bulbasaur>,  "level": 5 },
	{ "species": <Squirtle>,   "level": 5 },
]
```

(Drag species .tres files from the FileSystem into each dict's `species` field via the inspector.)

Save the scene.

- [ ] **Step 3 — Update `overworld_bootstrap.gd` to pass the full team**

Search for the line(s) where `trainer.build_opponent()` is called and replace with `trainer.build_team()`. Similarly, the wild-battle call path already uses `[wild_mon]` (a 1-element array) — no change there.

For example, replace:

```gdscript
battle.start([GameState.player_party[0]], [trainer.build_opponent()], ctx)
```

with:

```gdscript
battle.start(GameState.player_party, trainer.build_team(), ctx)
```

And the wild-battle call (search for `EncounterZone` or `wild_mon`):

```gdscript
battle.start(GameState.player_party, [wild_mon], ctx)
```

- [ ] **Step 4 — Implement forced switch in `battle.gd`**

Replace the player-faint branch in `_handle_faint`:

```gdscript
else:
	# Player-side faint.
	current_opponent_participants.erase(player_active_idx)
	if PartyHelpers.all_fainted(player_party):
		state = State.ENDED
		await _print_dialog("You are out of usable Pokémon!")
		var result := BattleResult.new()
		result.outcome = BattleResult.Outcome.LOSE
		battle_ended.emit(result)
		return
	await _open_party_screen_forced()
```

Add the helper:

```gdscript
func _open_party_screen_forced() -> void:
	state = State.FAINT_SWITCH
	_party_screen = PARTY_SCREEN.instantiate()
	add_child(_party_screen)
	_party_screen.slot_chosen.connect(_on_party_slot_chosen_forced)
	# No cancelled handler — FORCED_SWITCH disables cancel at the PartyScreen level.
	_party_screen.open(player_party, player_active_idx, PartyScreen.Mode.FORCED_SWITCH)

func _on_party_slot_chosen_forced(idx: int) -> void:
	_close_party_screen()
	await _switch_to(idx, true)
	# Forced switch doesn't spend the turn — back to action menu.
	_enter_action_menu()
```

- [ ] **Step 5 — Implement enemy team progression**

Replace the enemy-faint branch's tail (`state = State.ENDED; battle_ended.emit(WIN)`) in `_handle_faint`:

```gdscript
# Enemy faint path (existing body ends after the splits loop). Replace the
# "state = State.ENDED; battle_ended.emit(WIN)" block with:

if PartyHelpers.all_fainted(enemy_party):
	if context.is_trainer:
		await _print_dialog("The trainer was defeated!")
	state = State.ENDED
	var result := BattleResult.new()
	result.outcome = BattleResult.Outcome.WIN
	result.xp_gained = total_xp
	battle_ended.emit(result)
	return

# Trainer still has mons. Send the next.
enemy_active_idx = PartyHelpers.first_non_fainted(enemy_party)
enemy_mon = enemy_party[enemy_active_idx]
current_opponent_participants = [player_active_idx]
await _print_dialog("The trainer sent out %s!" % enemy_mon.species.species_name)
_apply_sprites()
_refresh_hp_bars(true)
_refresh_labels()
_enter_action_menu()
```

- [ ] **Step 6 — Run regression tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -gexit
```

Expected: 50/50. No tests added in this step; no regressions from integration work.

- [ ] **Step 7 — Manual checkpoints**

1. **Forced switch** — Wild battle, intentionally let Bulbasaur faint (pick a weak move; let enemy hit). Forced PartyScreen appears. CANCEL is absent from the submenu. Pick Charmander → "Go Charmander!" → battle continues from action menu.
2. **Team wipe** — Wild battle, let all 3 party members faint in succession. On the 3rd faint: "You are out of usable Pokémon!" → overworld, party still populated but all 3 at 0 HP. Press H to heal, confirm all are full again.
3. **Trainer team of 3** — Walk into Trainer1's sightline. Battle starts with Trainer1's Charmander. Beat it → "Charmander fainted!" → XP split → "The trainer sent out Bulbasaur!" → action menu. Beat Bulbasaur → Squirtle. Beat Squirtle → "The trainer was defeated!" → overworld, trainer marked defeated.
4. **Trainer RUN still blocked** — Re-triggering requires a fresh trainer; reset by restarting. Confirmed at step 2c.5; no regression this step.
5. **Mid-battle switch against trainer team** — Start trainer battle, FIGHT one round, POKéMON next round → switch to Charmander → enemy attacks → faint Charmander voluntarily in a later turn? No — let active die instead. Alternate: do voluntary switch + let Charmander participate in an enemy faint → verify XP splits among participants for that enemy (Bulbasaur who also dealt damage + Charmander who was active at KO).

- [ ] **Step 8 — Commit**

```bash
git add scripts/battle/battle.gd scripts/overworld/trainer.gd \
        scenes/overworld/Overworld.tscn scripts/overworld/overworld_bootstrap.gd
git commit -m "$(cat <<'EOF'
feat(phase2c): forced switch, team wipe, enemy trainer teams

- battle.gd _handle_faint:
  * Player faint: removes fainter from participant set. If PartyHelpers.
    all_fainted → LOSE. Else opens PartyScreen in FORCED_SWITCH mode;
    cancel disabled; on pick, _switch_to(idx, is_forced=true) and return
    to ACTION_MENU (no turn spent).
  * Enemy faint: after splitting XP, checks enemy_party. On full wipe,
    narrates "The trainer was defeated!" in trainer battles, emits WIN.
    Otherwise sends the next non-fainted enemy with "Trainer sent out X!",
    resets current_opponent_participants to [player_active_idx], returns
    to ACTION_MENU.
- trainer.gd:
  * opponent_species + opponent_level removed; @export var team: TrainerTeam.
  * build_opponent() -> build_team(): Array[PokemonInstance]. Empty/null
    team is a push_error.
- Overworld.tscn Trainer1: migrated to an inline TrainerTeam resource
  with 3 entries (Charmander L5, Bulbasaur L5, Squirtle L5) for the
  manual-checkpoint #3 full-team flow.
- overworld_bootstrap: battle.start now receives GameState.player_party
  directly (not a 1-wrap) and trainer.build_team() for trainer battles.

Suite: 50/50 (nothing added; no regressions). Phase 2c complete — party
of 6 + switching ships.

Co-Authored-By: Claude Opus 4 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

Run through after the plan is drafted (done inline before committing this doc):

**Spec coverage:**
- Scope/In items mapped to tasks:
  - `player_party: Array[PokemonInstance]` + `PARTY_MAX` + debug seed → 2c.3 ✓
  - ActionMenu / FIGHT / POKÉMON / BAG / RUN → 2c.5 ✓
  - Voluntary switch → 2c.7 ✓
  - Forced switch + fainted-slot rules → 2c.6 (ui mode) + 2c.8 (wire) ✓
  - Team wipe loss → 2c.8 ✓
  - Enemy trainer teams + "sent out X" narration → 2c.8 ✓
  - Enemy AI: reactive-only → 2c.8 (no AI code added; send-next-on-faint is the entire behavior) ✓
  - XP split among participants → 2c.1 (math) + 2c.7 (wire) ✓
  - Bench level-up narration rules → 2c.7 ✓
  - PartyScreen scene + 3 modes → 2c.4 (scene + reorder) + 2c.6 (submenu + battle modes) ✓
  - 1-page Summary → 2c.6 ✓
  - P keybind → 2c.4 ✓
  - Swap animation → 2c.4 ✓
  - TrainerTeam schema update → 2c.2 (resource) + 2c.8 (migrate Trainer1) ✓
  - Unit tests → 2c.1 + 2c.2 (10 new tests, suite 38→48) ✓
- Edge cases in spec mapped:
  - Single-member party on battle start → defensive in 2c.7 `start()` guard ✓
  - Forced-switch cancel disabled → 2c.6 `_submenu_options` + 2c.4 `_on_cancel` early-return ✓
  - Selecting active in SWITCH → 2c.6 SWITCH omitted if `_selected == _active_idx` ✓
  - RUN in trainer battle → 2c.5 ✓
  - Participant set idempotent adds → 2c.7 `has(idx)` guard ✓
  - Zero participants fallback → 2c.7 `_compute_participant_xp_split` defensive branch ✓
  - Multi-level bench → 2c.7 `_apply_bench_levelups` loop ✓
  - P keybind input lock → 2c.4 `input_locked = true/false` ✓
  - Empty TrainerTeam → 2c.8 `push_error` ✓
  - No save migration → N/A, noted in plan header ✓

**Placeholder scan:** the only "TODO" is `TODO(2d)` in the GameState debug-seed comment, which is intentional code signaling (per the spec itself). No `TBD` / `FIXME` / `fill in`.

**Type consistency:** checked — `player_active_idx` / `enemy_active_idx` / `current_opponent_participants` / `_party_screen` / `PARTY_SCREEN` used uniformly across steps. Method names match the spec (`_switch_to`, `_open_party_screen_*`, `_handle_faint`, `_apply_bench_levelups`, `_compute_participant_xp_split`). PartyScreen mode enum values match the spec.
