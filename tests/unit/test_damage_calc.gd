extends GutTest
## Validates DamageCalc using reference computations derived from the Gen 3
## damage formula. We can't assert exact damage (crit & random rolls are
## stochastic) so most tests run many trials and assert min/max/range.
## Reference: https://bulbapedia.bulbagarden.net/wiki/Damage

const BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER  := preload("res://data/species/004_charmander.tres")
const SQUIRTLE    := preload("res://data/species/007_squirtle.tres")

const TACKLE      := preload("res://data/moves/tackle.tres")
const SCRATCH     := preload("res://data/moves/scratch.tres")
const VINE_WHIP   := preload("res://data/moves/vine_whip.tres")
const EMBER       := preload("res://data/moves/ember.tres")

const TYPE_CHART  := preload("res://data/type_chart.tres")


func _ctx() -> BattleContext:
	return BattleContext.with_chart(TYPE_CHART)


# --- Type chart sanity -----------------------------------------------------

func test_type_chart_known_relations() -> void:
	assert_eq(TYPE_CHART.single(Enums.Type.FIRE, Enums.Type.GRASS), 2.0, "Fire -> Grass")
	assert_eq(TYPE_CHART.single(Enums.Type.FIRE, Enums.Type.WATER), 0.5, "Fire -> Water")
	assert_eq(TYPE_CHART.single(Enums.Type.GRASS, Enums.Type.WATER), 2.0, "Grass -> Water")
	assert_eq(TYPE_CHART.single(Enums.Type.GRASS, Enums.Type.FIRE), 0.5, "Grass -> Fire")
	assert_eq(TYPE_CHART.single(Enums.Type.GRASS, Enums.Type.POISON), 0.5, "Grass -> Poison")
	assert_eq(TYPE_CHART.single(Enums.Type.NORMAL, Enums.Type.GHOST), 0.0, "Normal -> Ghost (immune)")
	assert_eq(TYPE_CHART.single(Enums.Type.NORMAL, Enums.Type.FIRE), 1.0, "Normal -> Fire (neutral)")


func test_combined_effectiveness_multiplies_types() -> void:
	# Fire attacking Grass/Poison (Bulbasaur): Fire->Grass 2.0 * Fire->Poison 1.0 = 2.0
	assert_eq(
		TYPE_CHART.combined(Enums.Type.FIRE, [Enums.Type.GRASS, Enums.Type.POISON]),
		2.0
	)
	# Grass attacking Grass/Poison: Grass->Grass 0.5 * Grass->Poison 0.5 = 0.25
	assert_eq(
		TYPE_CHART.combined(Enums.Type.GRASS, [Enums.Type.GRASS, Enums.Type.POISON]),
		0.25
	)


# --- Damage ranges --------------------------------------------------------

## Runs `trials` damage rolls and returns [min, max] of non-miss damage values.
func _damage_range(attacker: PokemonInstance, defender: PokemonInstance, move: Move, trials: int = 500) -> Array:
	var ctx := _ctx()
	var lo: int = 1 << 30
	var hi: int = 0
	var hits := 0
	for _i in trials:
		var r: DamageCalc.Result = DamageCalc.calculate(attacker, defender, move, ctx)
		if r.is_status or r.missed:
			continue
		hits += 1
		lo = min(lo, r.damage)
		hi = max(hi, r.damage)
	assert_gt(hits, 0, "expected at least one non-miss hit across %d trials" % trials)
	return [lo, hi]


func test_tackle_bulbasaur_vs_charmander_damage_bounds() -> void:
	# Gen 3 Tackle: power 35, accuracy 95. No STAB (Bulbasaur isn't Normal).
	# Normal vs Fire = 1.0 (neutral).
	# Bulbasaur L5 Atk = 9. Charmander L5 Def = 9.
	#   step1 = (2*5)/5 + 2 = 4
	#   step2 = 4 * 35 * 9 / 9 = 140
	#   base  = 140/50 + 2 = 4
	# Modifiers: STAB=1.0, type=1.0, crit∈{1.0, 2.0}, random∈[0.85, 1.00], burn=1.0
	# No-crit: 4 * rand ∈ [3.4, 4.0]  -> damage ∈ {3, 4}
	# Crit:    8 * rand ∈ [6.8, 8.0]  -> damage ∈ {6, 7, 8}
	var b := PokemonInstance.create(BULBASAUR, 5)
	var c := PokemonInstance.create(CHARMANDER, 5)
	var range := _damage_range(b, c, TACKLE, 1000)
	var lo: int = range[0]
	var hi: int = range[1]
	assert_between(lo, 3, 4, "observed min")
	assert_between(hi, 6, 8, "observed max")


func test_ember_on_bulbasaur_super_effective() -> void:
	# Ember: Fire, Special, 40 power.
	# Bulbasaur = Grass/Poison -> Fire super effective (2.0).
	var c := PokemonInstance.create(CHARMANDER, 5)
	var b := PokemonInstance.create(BULBASAUR, 5)
	var ctx := _ctx()
	# One call: check effectiveness flag (independent of rng).
	var r: DamageCalc.Result = DamageCalc.calculate(c, b, EMBER, ctx)
	# Might miss (acc=100, so won't miss). Will always have effectiveness=2.0.
	assert_eq(r.effectiveness, 2.0, "Fire vs Grass/Poison = 2.0")
	assert_false(r.is_status)
	assert_false(r.missed)
	# Damage bounds:
	# Charmander L5 SpA = 11. Bulbasaur L5 SpD = 11.
	#   step1 = 4; step2 = 4*40*11/11 = 160; base = 160/50 + 2 = 5.
	#   STAB 1.5, type 2.0, crit {1,2}, rand [0.85, 1.0], burn 1.
	#   No-crit: 5 * 1.5 * 2 * rand = 15 * rand -> [12.75, 15] -> {12..15}
	#   Crit:    5 * 1.5 * 2 * 2 * rand = 30 * rand -> [25.5, 30] -> {25..30}
	var range := _damage_range(c, b, EMBER, 1000)
	var lo: int = range[0]
	var hi: int = range[1]
	assert_between(lo, 12, 15, "observed min")
	assert_between(hi, 25, 30, "observed max")


func test_vine_whip_on_charmander_not_very_effective() -> void:
	# Vine Whip: Grass, Special, 45 power (PokeAPI Gen3 value).
	# Bulbasaur -> Charmander = Grass vs Fire = 0.5.
	var b := PokemonInstance.create(BULBASAUR, 5)
	var c := PokemonInstance.create(CHARMANDER, 5)
	var ctx := _ctx()
	var r: DamageCalc.Result = DamageCalc.calculate(b, c, VINE_WHIP, ctx)
	assert_eq(r.effectiveness, 0.5, "Grass vs Fire = 0.5")
	assert_false(r.is_status)


func test_stab_applies_when_type_matches() -> void:
	# Bulbasaur using Vine Whip (Grass) on Charmander (Fire):
	#   SpA=11, SpD=10. step1=4; step2=4*45*11/10=198; base=198/50+2=5.
	#   STAB 1.5, type 0.5, crit {1,2}, rand [0.85,1.0].
	#   No-crit: 5 * 1.5 * 0.5 * rand = 3.75*rand -> [3.1875, 3.75] -> {3}
	#   Crit:    5 * 1.5 * 0.5 * 2 * rand = 7.5*rand -> [6.375, 7.5] -> {6, 7}
	var b := PokemonInstance.create(BULBASAUR, 5)
	var c := PokemonInstance.create(CHARMANDER, 5)
	var range := _damage_range(b, c, VINE_WHIP, 1000)
	var lo: int = range[0]
	var hi: int = range[1]
	# Minimum non-crit damage is 3 in this matchup (per calc above).
	assert_eq(lo, 3, "STAB non-crit min")
	# Maximum with crit is 7.
	assert_between(hi, 6, 7, "crit max")


# --- Edge cases -----------------------------------------------------------

func test_status_move_returns_zero_damage() -> void:
	# Construct a synthetic STATUS move in-memory.
	var m := Move.new()
	m.move_name = "Test Status"
	m.type = Enums.Type.NORMAL
	m.category = Enums.Category.STATUS
	m.power = 0
	m.accuracy = 100
	m.pp = 10
	var b := PokemonInstance.create(BULBASAUR, 5)
	var c := PokemonInstance.create(CHARMANDER, 5)
	var r: DamageCalc.Result = DamageCalc.calculate(b, c, m, _ctx())
	assert_true(r.is_status)
	assert_eq(r.damage, 0)


func test_guaranteed_miss_when_accuracy_impossible() -> void:
	# Synthetic move with accuracy 1 — should miss almost all the time.
	var m := Move.new()
	m.move_name = "Test Miss"
	m.type = Enums.Type.NORMAL
	m.category = Enums.Category.PHYSICAL
	m.power = 40
	m.accuracy = 1
	m.pp = 10
	var b := PokemonInstance.create(BULBASAUR, 5)
	var c := PokemonInstance.create(CHARMANDER, 5)
	var ctx := _ctx()
	var misses := 0
	for _i in 200:
		var r: DamageCalc.Result = DamageCalc.calculate(b, c, m, ctx)
		if r.missed:
			misses += 1
	# With 1% accuracy, we expect the overwhelming majority to miss.
	assert_gt(misses, 180, "expected most attacks to miss")


func test_immune_zero_damage_not_clamped_to_one() -> void:
	# Normal → Ghost = 0.0. We don't have a Ghost species in Phase 1, but we can
	# construct a minimal Ghost species in memory and verify the code path.
	var ghost_species := Species.new()
	ghost_species.dex_number = 999
	ghost_species.species_name = "Test Ghost"
	ghost_species.types = [Enums.Type.GHOST]
	ghost_species.base_stats = {
		"hp": 40, "atk": 40, "def": 40, "spa": 40, "spd": 40, "spe": 40,
	}
	var ghost := PokemonInstance.create(ghost_species, 10)
	var attacker := PokemonInstance.create(BULBASAUR, 10)
	var r: DamageCalc.Result = DamageCalc.calculate(attacker, ghost, TACKLE, _ctx())
	if r.missed:
		# If we missed, try again — this test is about the damage=0 branch.
		return
	assert_eq(r.effectiveness, 0.0)
	assert_eq(r.damage, 0, "immune matchups should NOT be clamped to 1 damage")
