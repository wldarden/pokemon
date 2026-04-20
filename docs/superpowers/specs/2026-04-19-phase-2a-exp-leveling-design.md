# Phase 2a — EXP gain + leveling up

**Date:** 2026-04-19
**Status:** Approved, ready for implementation planning
**Scope:** First sub-phase of Phase 2. Turns the "Bulbasaur gained N EXP!" message from Phase 1 into actual progression — the Pokémon accumulates experience, levels up mid-battle, and the player sees FR/LG-style stat-change and new-stats screens.

## Goal

When a player defeats an opposing Pokémon, their active Pokémon:

- accumulates experience points,
- levels up when crossing the threshold for its species' growth curve (including multi-level jumps from a large XP grant),
- recomputes its six stats using the Gen-3 formula,
- preserves damage taken (current HP gains the **absolute** HP delta, not a percentage), and
- the player sees two confirm-gated screens per level-up: a stat-change (delta) screen and a new-totals screen.

This also applies the Gen-3 **trainer 1.5× XP multiplier** for XP earned from trainer battles.

## Scope

### In

- All 6 Gen-3 growth curves: Medium Fast, Medium Slow, Fast, Slow, Erratic, Fluctuating (with piecewise formulas and `max(0, …)` clamp at low levels).
- `PokemonInstance.gain_exp(amount) -> Array[LevelUpEvent]` — mutates, returns a list of events when crossing one or more level thresholds.
- `_level_up` recomputes stats, applies HP delta to `current_hp`.
- Battle-scene integration: narrate each level-up with stat-change + new-totals screens before emitting `battle_ended`.
- Gen-3 XP formula: `(base_exp × enemy_level) / 7`, multiplied by 1.5 for trainer battles.
- Level cap at 100 (extra XP past L100 is discarded; gain_exp is a no-op).
- GUT tests for growth curves, multi-level-up, HP preservation, trainer multiplier, level-100 no-op.

### Out (deferred to other sub-phases)

- **Move learning on level-up** → Phase 2b. If a level-up would teach a move, we silently skip for now.
- **Evolution trigger** → Phase 2e.
- **Party of 6 / XP split across participants** → Phase 2c. Phase 2a is still 1-vs-1, so the only XP recipient is `player_party[0]`.
- **Lucky Egg, EXP Share, trainer EV yields** — Phase 3+.
- **Stat stages carrying level-up deltas** (no such thing in Gen 3 anyway).

## Architecture

Matches the Phase 1 style: pure-function modules for formulas, mutating methods on `PokemonInstance` for state, battle scene drives narration.

### New modules

**`scripts/data/growth_curve.gd`** — `class_name GrowthCurve extends RefCounted`. Static functions only:

```gdscript
static func total_exp_at(rate: int, level: int) -> int
# Returns the CUMULATIVE experience a Pokémon with this growth rate needs
# to HAVE REACHED at a given level. Clamped to max(0, …) for curves that
# dip negative at low levels (Medium Slow does at L1–L4).

static func level_for_exp(rate: int, total_exp: int) -> int
# Inverse: given a total XP value, return the highest level whose
# threshold is ≤ total_exp. Used as a sanity helper in tests.
```

The `rate` parameter is an `Enums.GrowthRate` integer.

**`scripts/data/level_up_event.gd`** — `class_name LevelUpEvent extends RefCounted`. Plain dataclass:

```gdscript
var old_level: int
var new_level: int
var old_stats: Dictionary   # {hp, atk, def, spa, spd, spe}
var new_stats: Dictionary
var stat_deltas: Dictionary # new - old per stat
var hp_delta: int           # how many HP points were added to current_hp
```

### `PokemonInstance` extensions

```gdscript
func gain_exp(amount: int) -> Array[LevelUpEvent]:
    # If already level 100: no-op. Does not mutate `experience`, returns [].
    # Otherwise: adds XP, loops while the new XP total crosses the next-level
    # threshold, calls _level_up() per crossing, returns all events in order.
    # `experience` is clamped at the L100 threshold so no stored value ever
    # exceeds the cap.

func exp_to_next_level() -> int:
    # Convenience for UI: how many more XP points until the next level.
    # Returns 0 at level 100.

func _level_up() -> LevelUpEvent:
    # Recompute stats at the new level, apply absolute HP delta to
    # current_hp (FR/LG rule), increment level, return the event payload.
```

### Battle scene integration

In `battle.gd`, `_handle_faint(enemy_mon)` currently:
1. Prints "Charmander fainted!"
2. Computes placeholder XP from `enemy.species.base_exp_yield`
3. Prints "Bulbasaur gained N EXP!"
4. Emits `battle_ended`.

The new flow inserts the XP application between steps 3 and 4:

1. Print "Charmander fainted!"
2. `var xp = _compute_xp_for_opponent(enemy_mon)` — includes 1.5× trainer multiplier when `context.is_trainer`.
3. Print "Bulbasaur gained N EXP!"
4. **New:** `var events = player_mon.gain_exp(xp)`
5. **New:** for each event: narrate the level-up (see UI section).
6. Emit `battle_ended(result)`.

HP bar tween on the player HUD refreshes after each level-up so the new max HP shows. Already integrated via `_refresh_hp_bars(false)` + `_refresh_labels()`.

### Trainer XP multiplier

Replace `_compute_xp_placeholder()` in `battle.gd` with `_compute_xp_for_opponent(mon)`:

```gdscript
func _compute_xp_for_opponent(mon: PokemonInstance) -> int:
    if mon.species.base_exp_yield <= 0:
        return 0
    var raw := mon.species.base_exp_yield * mon.level / 7
    if context.is_trainer:
        raw = raw * 3 / 2   # Gen 3 trainer bonus: 1.5x, integer-safe
    return max(1, raw)
```

## Growth curve formulas

All curves take a level `n` and return the cumulative XP needed to reach that level. Table from Bulbapedia's "Experience" article.

| Rate | Formula (for level n) | Notes |
|---|---|---|
| Medium Fast | `n³` | straightforward cube |
| Medium Slow | `(6/5)n³ − 15n² + 100n − 140` | clamp ≥ 0 at L1–L4 where it's negative |
| Fast | `(4/5)n³` | |
| Slow | `(5/4)n³` | |
| Erratic | piecewise (4 ranges: 1–50, 51–67, 68–97, 98–100) | |
| Fluctuating | piecewise (3 ranges: 1–14, 15–35, 36–100) | |

The piecewise formulas for Erratic and Fluctuating are standard — implementation will reference the exact formulas in the GrowthCurve module's comments. Tests hardcode the Bulbapedia table values at levels 1, 50, 100 as regression checks.

## Level-up UI

Two **confirm-gated screens** per level, shown in the dialog-box area. Implementation reuses the existing `DialogBox` Panel — no new scenes. During a level-up the `DialogBox` is temporarily widened to 232 px (covering the move-menu area, which is hidden during narration anyway) so the stat columns fit.

### Screen 1 — stat deltas

```
Bulbasaur grew to Lv. 6!

  HP  +3       SPA +2
  ATK +1       SPD +1
  DEF +1       SPE +2
```

- Header line uses the existing typewriter effect.
- Stat lines render instantly after the header finishes (two-column layout, approximate alignment — Kenney Mini is proportional so perfect padding isn't achievable without a monospace font).
- Wait for `ui_accept` before advancing.

### Screen 2 — new totals

```
Bulbasaur  L6

  HP  13/24    SPA 13
  ATK 10       SPD 13
  DEF 10       SPE 10
```

- No typewriter — instant display (player already read the header on screen 1).
- HP line shows **current/max** — so a Pokémon that leveled up while damaged sees e.g., `HP 13/24`, reflecting reality rather than a full bar.
- Wait for `ui_accept` before advancing.

After screen 2 dismisses, if there are more `LevelUpEvent`s in the queue (multi-level grant), loop back to screen 1 for the next event. Otherwise restore `DialogBox` to its normal width and continue to `battle_ended`.

## Data flow

```
_handle_faint(enemy_mon):
  await _print_dialog("Charmander fainted!")
  var xp = _compute_xp_for_opponent(enemy_mon)        # 1.5x if trainer
  await _print_dialog("Bulbasaur gained N EXP!")
  var events = player_mon.gain_exp(xp)                # mutates player_mon
  _refresh_hp_bars(false); _refresh_labels()          # reflects new max HP
  for event in events:
    await _show_level_up_screens(event)               # screens 1 & 2
  battle_ended.emit(result)
```

`_show_level_up_screens(event)` temporarily widens the dialog box, prints screen 1 (typewriter header + instant stat lines), awaits `ui_accept`, prints screen 2, awaits `ui_accept`, restores the dialog box.

## Testing

### GUT unit tests

New file `tests/unit/test_exp_leveling.gd`:

1. `GrowthCurve.total_exp_at` returns Bulbapedia values for each of 6 curves at levels 1, 50, 100 (reference tables hardcoded in test).
2. `gain_exp` returns empty array when under next-level threshold.
3. `gain_exp` returns a single event when crossing exactly one threshold.
4. `gain_exp` returns multiple events in order when one grant crosses several levels.
5. `LevelUpEvent.stat_deltas` matches hand-computed values for a Bulbasaur going L5 → L6.
6. HP preservation: Pokémon at half HP gains exactly `hp_delta` to `current_hp` (not percentage).
7. `gain_exp` at level 100 is a no-op, returns `[]` even for huge XP input.
8. `exp_to_next_level` returns correct remaining XP for a partial-level Pokémon.
9. Trainer XP multiplier: `_compute_xp_for_opponent` with `is_trainer=true` returns ⌊1.5× wild value⌋.

Target: ~9 new tests, pure-function, ~0.5 s total runtime. Brings suite to **25/25**.

### Manual checkpoints

1. Beat a L2 wild Pokémon with L5 Bulbasaur → see XP gain → (no level-up at that level) → back to overworld.
2. Grind several wins → cross the L5→L6 Medium Slow threshold → see screens 1 & 2 → battle continues with updated HP bar.
3. Beat the L5 trainer Charmander → earn 1.5× XP vs. an equivalent wild encounter.
4. Construct a scenario where gain_exp crosses 2 levels in one shot → observe two rounds of screens.

## Phase 1 compatibility

No save files exist yet (Phase 5+), so no migration concerns. `Species.growth_rate` is already populated for the 3 species from PokéAPI (all Medium Slow). No .tres regeneration needed.

## What this unblocks

- **2b (move learning):** the `_level_up()` hook is the natural attachment point — after recomputing stats, consult the species learnset and queue a "teach new move?" dialog.
- **2e (evolution):** same hook — check species evolution criteria against the new level.

## Open questions

None at time of approval.
