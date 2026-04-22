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

## Phase 2d — spawn intent across scene transitions. Keys:
##   scene (PackedScene), cell (Vector2i), facing (int from Direction enum).
## Set by the outgoing door, consumed and cleared by the receiving scene's _ready().
var next_spawn: Dictionary = {}

## Phase 2d — restore every party member to full HP, clear status, restore all PP.
## Idempotent (safe to call on a fully-healthy party). No-op on empty party.
func heal_party() -> void:
	for mon in player_party:
		if mon == null:
			continue
		mon.current_hp = mon.max_hp()
		mon.status = Enums.StatusCondition.NONE
		for slot in mon.moves:
			slot.pp_current = slot.move.pp

