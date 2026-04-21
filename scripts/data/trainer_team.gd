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
