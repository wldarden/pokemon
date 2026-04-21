# Phase 2b — Move learning on level-up

**Date:** 2026-04-21
**Status:** Approved, ready for implementation planning
**Scope:** Second sub-phase of Phase 2. Hooks into the 2a level-up flow so Pokémon actually learn moves at the levels their species learnset dictates — with FR/LG-style Y/N prompt and move-to-forget selection when already at 4 moves.

## Goal

When a Pokémon levels up (via the Phase 2a `LevelUpEvent` flow), after the stat screens finish, the battle scene consults the species' learnset. For each move the species learns at the new level:

- if unknown and the Pokémon has fewer than 4 moves → auto-learn silently (one dialog line).
- if unknown and the Pokémon already knows 4 moves → FR/LG replace flow (Y/N → pick a move to forget → confirm).
- if already known → silently skip.

This also unblocks Phase 2e (evolution), which uses the same post-level-up hook.

## Scope

### In

- Fetch **all moves** (~920) from PokéAPI in one-time batch via pagination (60 per page). Filter each move's `past_values` to Gen-3-accurate power/accuracy/PP (same logic we already use in fetch_pokeapi.py).
- Populate `Species.learnset` on the 3 starter species from PokéAPI's per-species `moves[]` array, filtered to **level-up method** in **Gen-3 version groups** (ruby-sapphire, firered-leafgreen, emerald). When gens disagree on level: `firered-leafgreen` > `emerald` > `ruby-sapphire`.
- `LearnsetResolver` helper: pure static function returning the moves learned at a given level.
- Battle-scene hook: between level-up screens and `battle_ended`, resolve new moves and drive the learn flow.
- Y/N prompt UI (reuses `MoveMenu` Panel with two buttons).
- Move-to-forget selector (reuses `MoveMenu` directly with its 4 buttons).
- GUT tests for `LearnsetResolver` and the `_already_knows` predicate.

### Out (deferred)

- **TM/HM / move tutor / egg moves** — only level-up method in 2b.
- **Moves for species beyond our 3 starters** — the learnset data is species-specific; we populate only the species we have. The ~920 move `.tres` files are downloaded once anyway, so adding a species later is purely a learnset-population step.
- **"Don't want to learn? Learn it later!" Move Reminder NPC** — classic FR/LG feature, Phase 3+.
- **Held-item bypass (Sketch, Mimic)** — nowhere near needed.
- **Mid-battle HM conflict edge cases** — none of our moves are HMs yet.

## Architecture

Matches the Phase 2a style: pure data helpers, mutating state on `PokemonInstance`, UI flow in `battle.gd`.

### Data fetch

Extending `tools/fetch_pokeapi.py` with a separable `--fetch-all-moves` subcommand (existing species/move fetch stays idempotent and separate):

1. `GET /v2/move/?limit=60&offset=N` to enumerate names (~16 list pages for ~920 moves).
2. For each name: `GET /v2/move/{name}/` → full detail with past_values.
3. Apply same Gen-3 override rule we already use (first `past_values` entry whose version_group generation ≥ 3 wins; current values used if no such entry).
4. Write `data/moves/{name_with_underscores}.tres` (e.g., `leech_seed.tres`, `razor_leaf.tres`).
5. **Idempotent**: skip moves whose `.tres` already exists (so re-runs don't redo work).
6. Polite to the API: 50 ms sleep between detail calls, 3× retry on network error with exponential backoff (200 ms, 500 ms, 1.5 s).
7. Expected runtime: ~5 minutes for the whole move catalog.

A second extension to the existing species fetch reads `moves[]` from each `/pokemon/{id}` response and writes the filtered learnset into the species `.tres`.

### `Species.learnset` format

`Array[Dictionary]`, one entry per (level, move) pair, sorted by ascending level:

```gdscript
@export var learnset: Array[Dictionary] = []
# Entry shape: {"level": int, "move_path": String}
# move_path is res://data/moves/foo.tres — resolved lazily at runtime.
```

Duplicates allowed (same move at multiple levels, rare but possible).

### `LearnsetResolver` (new)

`scripts/data/learnset_resolver.gd`:

```gdscript
class_name LearnsetResolver extends RefCounted

## Returns the Move resources a species learns at exactly this level.
## Loaded lazily so species .tres files don't need compile-time refs to
## every possible move in the game.
static func moves_learned_at(species: Species, level: int) -> Array[Move]:
    # Iterate species.learnset, collect entries where level matches, load()
    # each move_path into a typed Move, return the list.
    # If load() returns null (missing .tres), push_warning and skip — should
    # never happen since we fetch the full move catalog, but defensive.
```

Pure, testable without a running battle.

### Battle flow integration

In `battle.gd._handle_faint`, after the existing 2a level-up loop:

```gdscript
for event in events:
    await _show_level_up_screens(event)
    var new_moves: Array[Move] = LearnsetResolver.moves_learned_at(
        player_mon.species, event.new_level
    )
    for move in new_moves:
        if _already_knows(player_mon, move):
            continue   # silent skip
        await _try_learn_move(player_mon, move)
```

`_already_knows(mon, move)` iterates `mon.moves` and compares by move resource identity (same `Move` reference) — sufficient since we `load()` from a canonical path.

### `_try_learn_move` cases

1. **Free slot** (`mon.moves.size() < 4`):
    - append `MoveSlot.from_move(move)` (starts at full PP).
    - dialog: `"Bulbasaur learned Leech Seed!"`.

2. **Full (4 moves)**:
    - dialog: `"Bulbasaur is trying to learn Leech Seed..."` → `"But Bulbasaur already knows 4 moves."`
    - Y/N prompt: `"Should a move be forgotten to make room for Leech Seed?"`
    - **NO**: dialog: `"Bulbasaur did not learn Leech Seed."`. Done.
    - **YES**: show move-to-forget menu. Player picks an index.
        - **Confirm (ui_accept)**: replace `mon.moves[idx]` with the new move; dialog: `"Forgot Tackle and learned Leech Seed!"`.
        - **Cancel (ui_cancel)**: loop back to the Y/N prompt (matches FR/LG behavior where you can change your mind).

## UI

Both interactions reuse existing widgets — no new scenes.

### Y/N prompt

Repurposes the `MoveMenu` Panel. Two buttons (`YES` and `NO`) positioned on the top row of the menu's button grid. Labels set by the script at prompt time; the bottom two buttons are hidden. Cursor-outline selection identical to move menu; arrow keys navigate left/right, `ui_accept` confirms, `ui_cancel` is treated as NO.

Dialog box is widened (same as level-up screens) to display the full question text.

### Move-to-forget menu

Uses the `MoveMenu` Panel directly, unchanged. Labels populated from the Pokémon's current 4 moves. Same arrow-key + Enter flow as picking an attack in battle. `ui_cancel` backs out to the Y/N prompt.

### Helper shape

```gdscript
func _yes_no_prompt(question: String) -> bool
func _select_move_to_forget(mon: PokemonInstance) -> int   # -1 if cancelled
```

Both are async — each awaits a local signal/poll loop until the player presses a button.

## Data flow (end-to-end)

```
(enemy faints)
  → _handle_faint narrates XP, calls gain_exp (Phase 2a)
  → for each LevelUpEvent:
    → stat-deltas screen
    → new-totals screen
    → NEW: for each move in LearnsetResolver.moves_learned_at(...):
      → if known → skip silently
      → if slot free → append + "learned X!"
      → if 4 moves:
        → narrate "trying to learn X / already knows 4 moves"
        → Y/N prompt
          → NO → "did not learn X"
          → YES → forget-menu
            → confirm → "forgot Y and learned X!"
            → cancel  → loop back to Y/N
  → battle_ended.emit(result)
```

## Testing

### GUT unit tests — new `tests/unit/test_learnset.gd`

1. `LearnsetResolver.moves_learned_at` returns expected moves for Bulbasaur at L7 (Leech Seed), L10 (Vine Whip), L15 (Poison Powder + Sleep Powder), etc.
2. Returns empty array when no moves at that level.
3. Returns multiple moves when learnset has 2 entries at the same level (Bulbasaur L15).
4. Returns empty array when species has empty learnset.
5. `_already_knows` returns true when Pokémon has a `MoveSlot` with the given Move, false otherwise.

Target: ~5 new tests, pure function, <0.5 s runtime. Brings total to **34/34**.

### Manual checkpoints

1. **Free-slot path**: Bulbasaur at 2 moves (Tackle, Vine Whip), level it to L7 → see `"Bulbasaur learned Leech Seed!"` (one dialog line, no Y/N).
2. **4-move replace path, confirm**: get Bulbasaur to 4 moves (teach it naturally by leveling), trigger another level-up with a learnable move → Y/N → say YES → pick a move → see `"Forgot X and learned Y!"`.
3. **4-move replace path, decline**: same as above, say NO → see `"did not learn"`.
4. **Cancel during move selection**: same as above, YES → press Esc during move pick → returns to Y/N prompt.
5. **Multi-level with move learns**: set up XP grant that crosses 2 levels, both teach moves → screens play in order.
6. **Already-knows skip**: shouldn't be reachable naturally with our starters, but confirm silent-skip by inspection if engineered.

## Phase 2a compatibility

No changes to `LevelUpEvent` or `gain_exp`. The 2a level-up flow is unchanged; 2b bolts on after each stat-totals screen.

## What this unblocks

- **Phase 2e (evolution):** same post-level-up hook. Check species evolution criteria against the new level, play evolution animation, swap species reference.
- Future species additions: once we add species #10, #25, etc., the move data is already on disk — only learnset fields need to be populated from PokéAPI.

## Open questions

None at time of approval.
