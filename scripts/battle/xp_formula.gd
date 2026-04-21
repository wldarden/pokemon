class_name XpFormula
extends RefCounted
## Gen 3 experience reward formula.
##
## Phase 2a uses the 1v1 form (no participant split). Lucky Egg, EXP Share,
## and affection bonuses will bolt on in later phases.

## Floor(base_exp * enemy_level / 7), multiplied by 3/2 (integer-safe 1.5x)
## for trainer battles. Returns at least 1 for any fight against a species
## with non-zero base_exp_yield — never awards 0.
static func exp_for_kill(defeated: PokemonInstance, is_trainer: bool) -> int:
	if defeated == null or defeated.species == null:
		return 0
	if defeated.species.base_exp_yield <= 0:
		return 0
	var raw: int = defeated.species.base_exp_yield * defeated.level / 7
	if is_trainer:
		raw = raw * 3 / 2
	return max(1, raw)

## Phase 2c: split XP evenly across participants. Integer floor, with a min-1
## clamp so a small grant still reaches every participant. Returns 0 when the
## input total is 0 (no phantom XP when there was nothing to give).
static func split_among_participants(total: int, count: int) -> int:
	if total <= 0 or count <= 0:
		return 0
	var each: int = total / count
	return max(1, each)
