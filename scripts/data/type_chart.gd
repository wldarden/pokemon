class_name TypeChart
extends Resource
## Type effectiveness chart. Stored as a flat dictionary keyed by
## "attacker_type_id:defender_type_id" → float multiplier (0, 0.5, 1.0, 2.0).
## Missing entries default to 1.0 (neutral).

@export var relations: Dictionary = {}

## Returns the multiplier for a single attacker type against a single defender type.
func single(attacker: int, defender: int) -> float:
	var key := "%d:%d" % [attacker, defender]
	if relations.has(key):
		return float(relations[key])
	return 1.0

## Computes the combined multiplier for an attack of `attacker_type` against
## a Pokémon whose types are `defender_types` (1 or 2 entries).
## Multiplies per-type multipliers together (standard Pokémon rule).
func combined(attacker_type: int, defender_types: Array) -> float:
	var m := 1.0
	for dt in defender_types:
		m *= single(attacker_type, int(dt))
	return m
