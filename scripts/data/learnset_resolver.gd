class_name LearnsetResolver
extends RefCounted
## Resolves a Species' level-up learnset into Move resources on demand.
##
## Species.learnset entries are {"level": int, "move_path": String} where
## move_path points at res://data/moves/<name>.tres. We load lazily so a
## species .tres doesn't need compile-time ExtResource refs to every
## possible move in the game.

## All Moves a species learns at exactly `level`, sorted by move name so
## two moves at the same level have a stable order.
static func moves_learned_at(species: Species, level: int) -> Array[Move]:
	var result: Array[Move] = []
	if species == null:
		return result
	for entry in species.learnset:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("level", -1)) != level:
			continue
		var path := String(entry.get("move_path", ""))
		if path.is_empty():
			continue
		var move := load(path) as Move
		if move == null:
			push_warning("LearnsetResolver: failed to load move at %s" % path)
			continue
		result.append(move)
	return result

## True if the Pokémon already has a MoveSlot for this Move resource.
## Identity comparison is safe because load() caches by path — two calls
## for the same res:// path return the same instance.
static func already_knows(mon: PokemonInstance, move: Move) -> bool:
	if mon == null or move == null:
		return false
	for slot in mon.moves:
		if slot.move == move:
			return true
	return false
