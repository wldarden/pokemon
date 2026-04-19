class_name BattleContext
extends RefCounted
## Per-battle data passed into DamageCalc. Separate from BattleState so tests
## can construct it without a running battle.

# Whether this is a trainer battle (Phase 2 will gate run/catch/prize-money on this).
var is_trainer: bool = false

# Weather — Phase 2+. Phase 1 is always NONE.
enum Weather { NONE = 0, SUN, RAIN, SANDSTORM, HAIL }
var weather: int = Weather.NONE

# Shared type chart reference. Required for DamageCalc.
var type_chart: TypeChart

# RNG — inject for deterministic tests.
var rng: RandomNumberGenerator

func _init() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()

static func with_chart(chart: TypeChart) -> BattleContext:
	var ctx := BattleContext.new()
	ctx.type_chart = chart
	return ctx
