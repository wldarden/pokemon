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
