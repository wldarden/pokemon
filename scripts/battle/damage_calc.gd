class_name DamageCalc
extends RefCounted
## Pure-function damage calculator implementing the Gen 3 (FireRed/LeafGreen)
## damage formula.
##
## Reference: https://bulbapedia.bulbagarden.net/wiki/Damage (Gen I–IV section)
##
##     base   = floor(floor(floor((2*L / 5) + 2) * Power * A / D) / 50) + 2
##     damage = floor(base * STAB * Type * Crit * Random * Burn * Weather * Badge)
##
## Status moves return zero damage and `damage_flag=STATUS_MOVE`.

const CRIT_RATE_BASE := 16   # 1 in 16 in Gen 3 (no crit boosts).
const RANDOM_MIN_PCT := 85   # 85..100 integer percent range.

class Result:
	extends RefCounted
	var damage: int = 0
	var missed: bool = false
	var crit: bool = false
	var effectiveness: float = 1.0  # 0, 0.25, 0.5, 1.0, 2.0, 4.0
	var is_status: bool = false     # move category is STATUS → no damage calc

	func describe_effectiveness() -> String:
		if effectiveness == 0.0: return "no_effect"
		if effectiveness < 1.0:  return "not_very_effective"
		if effectiveness > 1.0:  return "super_effective"
		return "neutral"

## `attacker`, `defender` are PokemonInstances. `move` is a Move resource.
## `context` is a BattleContext (provides type_chart, rng, is_trainer, weather).
static func calculate(
	attacker: PokemonInstance,
	defender: PokemonInstance,
	move: Move,
	context: BattleContext
) -> Result:
	var result := Result.new()

	if move.category == Enums.Category.STATUS:
		result.is_status = true
		return result

	# --- Accuracy check.
	if move.accuracy > 0:
		var roll := context.rng.randi_range(1, 100)
		if roll > move.accuracy:
			result.missed = true
			return result

	# --- Gather inputs.
	var level: int = attacker.level
	var power: int = move.power

	var attack_stat: int
	var defense_stat: int
	if move.category == Enums.Category.PHYSICAL:
		attack_stat = attacker.stat(Enums.StatKey.ATTACK)
		defense_stat = defender.stat(Enums.StatKey.DEFENSE)
	else:  # SPECIAL
		attack_stat = attacker.stat(Enums.StatKey.SP_ATTACK)
		defense_stat = defender.stat(Enums.StatKey.SP_DEFENSE)

	# --- Base damage (with per-step floors, Gen 3 convention).
	var step1: int = (2 * level) / 5 + 2
	var step2: int = step1 * power * attack_stat / defense_stat
	var step3: int = step2 / 50 + 2
	var base: float = float(step3)

	# --- Modifiers.
	# STAB.
	var stab: float = 1.5 if attacker.type_list().has(move.type) else 1.0

	# Type effectiveness.
	var type_mult: float = context.type_chart.combined(move.type, defender.type_list())
	result.effectiveness = type_mult

	# Critical hit. Gen 3: base rate 1/16. Multiplier 2.0.
	var crit_mult: float = 1.0
	if context.rng.randi_range(1, CRIT_RATE_BASE) == 1:
		crit_mult = 2.0
		result.crit = true

	# Random factor: 85..100 integer percent.
	var rand_mult: float = float(context.rng.randi_range(RANDOM_MIN_PCT, 100)) / 100.0

	# Burn halves physical damage in Gen 3.
	var burn_mult: float = 1.0
	if attacker.status == Enums.StatusCondition.BURN and move.category == Enums.Category.PHYSICAL:
		burn_mult = 0.5

	# Phase 1: weather, badge, other all 1.0.

	var damage_f: float = base * stab * type_mult * crit_mult * rand_mult * burn_mult
	var damage: int = int(floor(damage_f))

	# If type immunity (mult=0), damage is 0 — skip the min-1 clamp.
	if type_mult > 0.0 and damage < 1:
		damage = 1

	result.damage = damage
	return result
