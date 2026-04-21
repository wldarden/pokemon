# Phase 2c — Party of 6 + switching

**Date:** 2026-04-21
**Status:** Approved, ready for implementation planning
**Scope:** Third sub-phase of Phase 2. Replaces Phase 1's hardcoded "one Pokémon on each side" with full FR/LG-style teams: up to 6 per side, voluntary and forced switching in battle, enemy trainers with multi-Pokémon teams, participant-split XP, and a reusable PartyScreen accessible from both battle and overworld.

## Goal

The player can field and manage a party of up to 6 Pokémon. Enemy trainers do the same. In battle, the player can switch their active Pokémon voluntarily via a top-level POKéMON menu, and is forced to pick a replacement when the active Pokémon faints (unless the whole party is wiped, which ends the battle as a loss). Enemy trainers send out the next Pokémon on faint until their team is wiped. Participants in a single enemy mon's defeat share the XP. From the overworld, pressing P opens the PartyScreen in reorder mode so the player can choose the lead Pokémon for the next battle.

## Scope

### In

- `GameState.player_party: Array[PokemonInstance]` typed, max 6 (`const PARTY_MAX := 6`).
- Debug-seeded party: 3 Pokémon at boot (one of each starter, varied levels, one at mid-HP to exercise the low-HP UI). Marked with a `# TODO(2d):` comment to be removed when starter selection lands.
- **Battle top-level menu** — FR/LG 2×2: FIGHT / POKéMON / BAG / RUN.
  - FIGHT → existing move grid (unchanged).
  - POKéMON → PartyScreen in SWITCH_IN_BATTLE mode.
  - BAG → greyed out, no action (Phase 3+).
  - RUN → works in wild battles (instant escape for now; proper formula is Phase 3+), disabled-with-narration in trainer battles.
- **Voluntary switching** — picking a non-active, non-fainted slot swaps the active Pokémon; the switch counts as the player's action for the turn (enemy attacks after the switch completes).
- **Forced switching** — on active-Pokémon faint with teammates remaining, open PartyScreen in FORCED_SWITCH mode (CANCEL disabled, fainted slots un-selectable). Does not cost a turn — the player returns to the action menu.
- **Team wipe loss** — battle ends as LOSE only when every player Pokémon is fainted.
- **Enemy trainer teams** — `TrainerTeam` Resource with an ordered list of `{species, level, moves}` entries. On enemy faint, if the trainer has more, narrate `"{Trainer} sent out {Next}!"` and continue; battle ends as WIN only on full-team wipe.
- **Enemy trainer AI** — reactive only: sends next mon on faint, no preemptive tactical switching.
- **XP split among participants** — track the set of player indices that were active during each enemy mon's lifetime; on KO, split XP evenly with `max(1, floor(total / count))` per participant. Remainder discarded (FR/LG rule).
- **Bench level-up narration** — benched participants' level-ups are applied silently (no stat-delta screens); moves are auto-learned if a slot is free, silently skipped otherwise (no replace-prompt for benched mons).
- **PartyScreen scene** — standalone `scenes/ui/PartyScreen.tscn` usable by Battle and Overworld. Three modes:
  - `SWITCH_IN_BATTLE` — cancelable; slot → submenu `SUMMARY / SWITCH / CANCEL`.
  - `FORCED_SWITCH` — no cancel; fainted slots un-selectable; submenu shows `SUMMARY / SWITCH` only.
  - `OVERWORLD_REORDER` — pick two slots to swap, animate the swap, stay open for more swaps; B closes.
- **1-page Summary view** inside PartyScreen — species/level/EXP header, stats grid, move list. Collapses FR/LG's 3 pages (Info, Skills, Moves).
- **Overworld P keybind** — opens PartyScreen in OVERWORLD_REORDER mode. Locks player input while open.
- **Swap animation** — when two party slots swap, both panels tween to each other's positions over ~0.25 s.
- Unit tests for the pure-function math + helpers (XP split, party helpers, `TrainerTeam.build_instances`).

### Out (deferred to other sub-phases)

- **Starter-selection scene** → Phase 2d.
- **Catching Pokémon** → Phase 3+.
- **Bag / items** (including greyed BAG entry's real behavior and held items) → Phase 3+.
- **Pokémon Center healing** → Phase 2d.
- **EXP Share / Lucky Egg** → Phase 3+.
- **Preemptive enemy trainer switching AI** → Phase 3+.
- **Full 3-page Summary screen** (Info / Skills / Moves) — needs items + Pokédex content to justify the extra pages.
- **Run-escape odds formula** — Phase 2c uses "always escape" for wild battles.
- **Box / PC storage** for parties over 6 → Phase 3+.
- **Pokédex UI** and seen/caught updates from PartyScreen → Phase 3+.

## Architecture

Style matches earlier phases: flat class hierarchy, pure-function modules for math, mutating methods on `PokemonInstance` / `GameState` for runtime state, battle scene orchestrates narration.

### New files

- `scenes/ui/PartyScreen.tscn` — CanvasLayer-rooted, 240×160 full viewport. Slots laid out as one prominent lead on the left + a 5-tall stack on the right (one layout question already settled with mockups).
- `scripts/ui/party_screen.gd` — the controller:

  ```gdscript
  class_name PartyScreen extends CanvasLayer

  enum Mode { SWITCH_IN_BATTLE, FORCED_SWITCH, OVERWORLD_REORDER }

  signal slot_chosen(idx: int)         # SWITCH_IN_BATTLE, FORCED_SWITCH
  signal swap_requested(a: int, b: int)  # OVERWORLD_REORDER
  signal cancelled

  func open(party: Array, active_idx: int, mode: int) -> void
  func close() -> void
  ```

  Summary view is a child Panel inside the same scene, toggled internally (no external signal).

- `scripts/data/trainer_team.gd` — `class_name TrainerTeam extends Resource`. Ordered entries:

  ```gdscript
  @export var entries: Array[Dictionary] = []
  # Each dict:
  #   species: Species          (required)
  #   level:   int              (required)
  #   moves:   Array[Move]      (optional — empty means "use DefaultMovesets")

  func build_instances() -> Array[PokemonInstance]
      # Per entry: resolve default moves via DefaultMovesets.for_species() when
      # `moves` is empty, else use the provided Move resources. Construct a
      # PokemonInstance at the stated level via PokemonInstance.create() and
      # return the ordered array.
  ```

- `scripts/battle/party_helpers.gd` — `class_name PartyHelpers extends RefCounted`. Static helpers:

  ```gdscript
  static func first_non_fainted(party: Array) -> int
  static func all_fainted(party: Array) -> bool
  static func can_switch_to(party: Array, idx: int, active_idx: int) -> bool
  ```

- `tests/unit/test_party_switching.gd` — new GUT suite (~10 tests).

### Modified files

- `scripts/globals/game_state.gd`
  - Type `player_party: Array[PokemonInstance]`.
  - `const PARTY_MAX := 6`.
  - Add `_ready() -> void` that calls `_debug_seed_party()` when the array is empty, populating 3 placeholder Pokémon. `# TODO(2d):` comment.

- `scripts/battle/xp_formula.gd`
  - Add `static func split_among_participants(total: int, count: int) -> int` — returns `max(1, floor(total / count))` for `total > 0`, else 0.

- `scripts/battle/battle.gd` (bulk of the change — grows ~300 lines)
  - **State fields:**
    - Drop `player_mon`, `enemy_mon` instance vars. Replace reads with local rebinding at every switch-in (`player_mon = player_party[player_active_idx]`). `player_mon` / `enemy_mon` remain as *vars* (not accessors) that are reassigned on switch for consistency with the current style.
    - Add `player_active_idx: int`, `enemy_active_idx: int`.
    - Add `current_opponent_participants: Array[int]` — set-semantics, indices into `player_party`.
  - **State enum changes:**
    - Rename `CHOOSE_ACTION` → `MOVE_MENU` (the existing state's behavior is "waiting for a move selection", which is now only one possible top-level choice).
    - Add `ACTION_MENU` — the 2×2 FIGHT/POKéMON/BAG/RUN picker.
    - Add `PARTY_MENU` — a PartyScreen is open from the action menu.
    - Add `SWITCHING_IN` — narration for "Come back! / Go!" is playing.
    - Add `FAINT_SWITCH` — forced-switch PartyScreen is open.
    - Final enum: `{BOOTING, ACTION_MENU, MOVE_MENU, PARTY_MENU, SWITCHING_IN, FAINT_SWITCH, RESOLVING, ENDED}`.
  - **New methods:**
    - `_enter_action_menu()` — state = ACTION_MENU, show the 2×2, hide move menu.
    - `_enter_move_menu()` — state = MOVE_MENU, existing move-grid behavior.
    - `_open_party_screen(mode: int) -> void` — instantiate `PartyScreen`, `add_child`, connect signals, call `open(player_party, player_active_idx, mode)`.
    - `_switch_to(idx: int, is_forced: bool) -> void` — narrate "Come back!", update `player_active_idx`, add to participants, re-apply sprites/HUD, narrate "Go!". When not forced, transition to enemy-attack-only resolve; when forced, transition back to `_enter_action_menu()`.
    - `_narrate_send_out(side: String, mon: PokemonInstance)` — "{Trainer} sent out {Name}!" or "Go, {Name}!".
    - `_check_team_wipe(side: String) -> bool`.
    - `_compute_participant_xp_split(total: int) -> Dictionary` — `{participant_idx: xp}`.
    - `_apply_bench_levelups(mon, events)` — silent level-up + auto-learn-or-skip loop.
  - **`_handle_faint(mon)` rewired:** per-side branching, participant cleanup, team-wipe check, and (on win path) per-participant XP distribution + narration.
  - **Top-level menu input handling:** extend `_handle_menu_input()` to branch on state (ACTION_MENU navigates the 2×2, MOVE_MENU uses existing code). RUN submitted in ACTION_MENU runs different logic for trainer vs wild.

- `scenes/battle/Battle.tscn`
  - Add `ActionMenu` Panel (same dimensions + position as MoveMenu; 2×2 cells labelled FIGHT/POKéMON/BAG/RUN). Reuse the existing Cursor node — `_update_cursor_position()` already takes a target button, so it just needs per-state "which button array?" wiring.
  - `PartyScreen` is NOT baked into the tree — preloaded and instantiated on demand.

- `scripts/overworld/trainer.gd`
  - Remove `opponent_species: Species` + `opponent_level: int`.
  - Add `@export var team: TrainerTeam`.
  - `build_opponent()` → `build_team() -> Array[PokemonInstance]` delegating to `team.build_instances()`.
  - Defensive: `push_error` + refuse to trigger battle if `team` is null or empty.

- `scenes/overworld/Overworld.tscn`
  - Migrate `Trainer1`'s `opponent_species` / `opponent_level` into an inline `TrainerTeam` sub-resource with one entry. No new trainers this phase — test matrix extends the existing one to a 3-mon team for manual checkpoint 7.

- `scripts/overworld/overworld_bootstrap.gd`
  - Pass `GameState.player_party` (full array, not a 1-wrap) to `battle.start()`.
  - Pass `trainer.build_team()` for trainer battles.
  - Add `P` keybind handler: instantiate PartyScreen in OVERWORLD_REORDER mode, lock player input while open, unlock on close.

- `scripts/battle/battle_result.gd` — no change. Outcome enum already covers WIN / LOSE.
- `scripts/data/pokemon_instance.gd` — no change. Participant tracking is battle-scoped.

### Key simplifying rules

- The battle's visible HUD always shows exactly one player mon and one enemy mon (the active ones). Switching is a sprite swap + HP-bar retween, not a multi-slot grid. Matches FR/LG.
- "Set semantics" for `current_opponent_participants` is enforced by `if not array.has(idx): array.append(idx)`. No separate Set class.
- PartyScreen is single-instance — only one open at a time. Entering it from battle pushes it on top of the battle CanvasLayer; entering from overworld pushes it on top of the overworld.

## Data flow

Four scenarios cover every path.

### A — Voluntary in-battle switch (costs a turn)

```
_enter_action_menu()                                  # FIGHT / POKéMON / BAG / RUN
player picks POKéMON:
  _open_party_screen(Mode.SWITCH_IN_BATTLE)
    PartyScreen emits slot_chosen(idx) or cancelled
    # cancel returns to action menu, no turn spent
  _switch_to(idx, is_forced=false):
    await _print_dialog("Come back, {current}!")
    player_active_idx = idx
    if not current_opponent_participants.has(idx):
        current_opponent_participants.append(idx)
    _apply_sprites(); _refresh_hp_bars(true); _refresh_labels()
    await _print_dialog("Go, {new}!")
  enemy_move = _choose_enemy_move()
  _resolve_turn(null, enemy_move)                     # player skips attack
```

### B — Forced switch after player faint (free)

```
_handle_faint(player_mon):
  await _print_dialog("{player_mon} fainted!")
  current_opponent_participants.erase(player_active_idx)  # fainter drops from XP set
  if PartyHelpers.all_fainted(player_party):
    await _print_dialog("You are out of usable Pokémon!")
    battle_ended.emit(lose)
    return
  _open_party_screen(Mode.FORCED_SWITCH)             # cancel disabled
    slot_chosen(idx)
  await _switch_to(idx, is_forced=true)              # doesn't spend the turn
  _enter_action_menu()
```

### C — Enemy faint / next opponent (trainer battle)

```
_handle_faint(enemy_mon):
  await _print_dialog("{enemy_mon} fainted!")
  var total_xp = _compute_xp_for_opponent(enemy_mon)       # includes 1.5× if trainer
  var splits = _compute_participant_xp_split(total_xp)     # {idx: xp_each}
  for idx in current_opponent_participants:
    var amount = splits[idx]
    var mon = player_party[idx]
    await _print_dialog("{mon} gained {amount} EXP!")
    var events = mon.gain_exp(amount)
    if mon == player_mon and not events.is_empty():
      _refresh_hp_bars(false); _refresh_labels()
      for event in events:
        await _show_level_up_screens(event)                # existing Phase 2a UI
        # Phase 2b learnset flow:
        for move in LearnsetResolver.moves_learned_at(mon.species, event.new_level):
          if not LearnsetResolver.already_knows(mon, move):
            await _try_learn_move(mon, move)
    elif not events.is_empty():
      _apply_bench_levelups(mon, events)                   # silent

  if PartyHelpers.all_fainted(enemy_party):
    if context.is_trainer:
      await _print_dialog("{trainer_name} was defeated!")
    battle_ended.emit(win)
    return

  # Trainer still has mons.
  enemy_active_idx = PartyHelpers.first_non_fainted(enemy_party)
  enemy_mon = enemy_party[enemy_active_idx]
  current_opponent_participants = [player_active_idx]      # reset for new opponent
  await _narrate_send_out("enemy", enemy_mon)
  _apply_sprites(); _refresh_hp_bars(true); _refresh_labels()
  _enter_action_menu()
```

### D — Overworld reorder

```
Player._process() detects P pressed and not is_moving:
  Player.input_locked = true
  var screen = preload(...).instantiate()
  get_tree().root.add_child(screen)
  screen.open(GameState.player_party, 0, Mode.OVERWORLD_REORDER)
  screen.swap_requested.connect(_on_swap)
  screen.cancelled.connect(_on_close)

_on_swap(a, b):
  var tmp = GameState.player_party[a]
  GameState.player_party[a] = GameState.player_party[b]
  GameState.player_party[b] = tmp
  # PartyScreen plays the slot-tween animation and refreshes its display.

_on_close():
  screen.queue_free()
  Player.input_locked = false
```

### Participant-set rules (summary)

- On voluntary switch-in: add new active's index to the set (idempotent).
- On player faint: remove the fainter's index from the set.
- On enemy send-next: reset set to `[player_active_idx]`.
- On enemy faint: split `total_xp` among every index still in the set.

## UI layout

See the brainstorm mockups in `.superpowers/brainstorm/.../ui-layout.html` (or regenerate them when revisiting). Four screens:

1. **Battle action menu** — 2×2 replacing the "jump straight to moves" flow. FIGHT / POKéMON / BAG (greyed) / RUN.
2. **Party screen main list** — lead (active) Pokémon on the left as a large panel; the other 5 slots stack on the right. Fainted slots are dimmed and tagged `FNT`. Empty slots are grey stubs with `—`.
3. **Party screen submenu** — opens to the right of a selected non-active slot: `SUMMARY / SWITCH / CANCEL`. Selecting the active slot shows `SUMMARY / CANCEL`.
4. **1-page Summary view** — header `{NAME} :L{LEVEL}` with EXP-to-next, stats grid on the left (HP/ATK/DEF/SPA/SPD/SPE + Type + Nature), 4-move list on the right.

All layouts render within the native 240×160 canvas.

## Art assets

Three source sheets (already in `assets/Pokemon Sprites/`, gitignored rips) feed this phase's UI:

- `Game Boy Advance - Pokemon FireRed _ LeafGreen - Battle Effects - HP Bars & In-battle Menu.png` — top-level action menu frame + HP-bar graphics.
- `Game Boy Advance - Pokemon FireRed _ LeafGreen - Menu Elements - Interface & Bag Screens.png` — PartyScreen chrome, submenu borders, Summary page frame.
- `Game Boy Advance - Pokemon FireRed _ LeafGreen - Miscellaneous - Fonts.png` — bitmap fonts for any text that needs a real Pokémon feel instead of Kenney Mini.

Extraction tools follow the `tools/build_frlg_atlas.py` / `tools/build_npc_atlas.py` pattern — a new tool per sheet is expected during implementation.

## Edge cases

- **Empty or single-member party on battle start** — `battle.start()` asserts `player_party.size() >= 1`. If size == 1, POKéMON still opens; SWITCH is greyed on the single slot.
- **Forced-switch mode cancel** — B press is ignored in the party main list; submenu omits CANCEL; fainted-slot selection shows "No usable Pokémon there!" and stays open.
- **Selecting the active Pokémon in SWITCH mode** — submenu drops SWITCH, shows `SUMMARY / CANCEL` only.
- **RUN in a trainer battle** — narrates `"No! There's no running from a trainer battle!"` and returns to the action menu.
- **Participant set: idempotent adds** — `if not has: append`.
- **Zero participants on enemy faint** — defensive fallback to `[player_active_idx]` to avoid divide-by-zero.
- **Multi-level-up for a benched participant** — each event recomputes stats; auto-learn for free slots; no replace-prompt for benched mons.
- **Benched participants learn order** — level-ups for each mon process in party-order, in event-order within each mon, so narration is deterministic.
- **P keybind during dialog or battle** — `Player.input_locked` gate extended to cover PartyScreen lifetime.
- **Trainer with empty `team`** — `trainer.gd._ready()` `push_error`s and refuses to enter battle.
- **Save compatibility** — no saves exist (Phase 5+), so no migration concerns.

## Testing

### GUT unit tests — `tests/unit/test_party_switching.gd`

1. `XpFormula.split_among_participants(30, 3) == 10` — even split.
2. `XpFormula.split_among_participants(10, 3) == 3` — floor, remainder discarded.
3. `XpFormula.split_among_participants(1, 3) == 1` — min-1 clamp when `total > 0`.
4. `XpFormula.split_among_participants(0, 3) == 0` — no XP given.
5. `PartyHelpers.first_non_fainted` finds the first alive index.
6. `PartyHelpers.first_non_fainted` returns -1 on a fully-fainted party.
7. `PartyHelpers.all_fainted` true when every mon fainted.
8. `PartyHelpers.all_fainted` false when at least one is alive.
9. `PartyHelpers.can_switch_to` false for fainted slot, false for active slot, true for alive non-active slot (3 asserts in one test OK).
10. `TrainerTeam.build_instances()` with 3 entries yields 3 `PokemonInstance`s with the right species and levels, default moves populated.

Target: ~10 new tests. Suite goes from 38/38 to **~48/48**, still <1 s total runtime.

### Manual checkpoints

1. **Overworld party screen** — boot overworld, press P, see 3 seeded mons. Arrow keys navigate; submenu opens on A; CANCEL / B closes.
2. **Overworld reorder** — in party screen, swap slots 0 and 1 → animation plays → close → reopen → order persists → start a battle → verify new slot 0 is the starter.
3. **Wild battle basic path** — FIGHT → win → single-recipient XP (no split). Regression on phase 2a/2b.
4. **Wild battle voluntary switch** — POKéMON → pick slot 1 → "Come back / Go!" → enemy attacks → win → both mons earn XP, math matches formula.
5. **Forced switch** — let active mon faint → forced PartyScreen appears with CANCEL hidden and fainted slot greyed → pick a non-fainted slot → battle continues.
6. **Team wipe (lose)** — faint all 3 mons → "You are out of usable Pokémon!" → back to overworld, party persists (all fainted). H debug key restores.
7. **Trainer with 3 mons** — extend `route_0_trainer_1`'s team to 3 entries; beat each in sequence; "Trainer sent out X!" narration between mons; "Trainer was defeated!" at end.
8. **Trainer RUN blocked** — trainer battle → RUN → "No! There's no running..." → back to action menu.
9. **Wild RUN works** — wild battle → RUN → escape → back to overworld.
10. **Summary page** — party screen → A on a slot → SUMMARY → stats and moves render → B closes.

## Phase 1 / 2a / 2b compatibility

- No save files exist yet — no migration.
- `Species.growth_rate`, `Species.base_stats`, `LearnsetResolver`, `XpFormula`, `DefaultMovesets` — all unchanged. Phase 2c builds on top.
- `BattleResult.Outcome.WIN` / `LOSE` still cover every ending Phase 2c produces.
- Existing `Trainer1` instance in `Overworld.tscn` gets its exports migrated to a `TrainerTeam` sub-resource with one entry — behavior-preserving for that trainer until its team is expanded for the phase-2c manual checkpoint.

## What this unblocks

- **Phase 2d (Pokémon Centers / dialog system):** the overworld PartyScreen entry point is a prototype for "NPC heals your party" — swap the P-key trigger for an NPC-interact trigger and add the heal animation.
- **Phase 2e (Evolution):** `_level_up()` already produces `LevelUpEvent`s for bench participants; evolution criteria can hook those events for any mon, not just the active one.
- **Phase 3+ (Catching):** a caught Pokémon appends to `GameState.player_party`; when size == `PARTY_MAX`, Box/PC logic kicks in.
- **Phase 3+ (Bag / items):** the greyed BAG cell in the action menu is the future insertion point.

## Open questions

None at time of approval.
