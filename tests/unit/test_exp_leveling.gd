extends GutTest
## Phase 2a: validates growth curves, gain_exp / _level_up, HP-preservation
## rule, and the trainer XP multiplier.
## Reference: https://bulbapedia.bulbagarden.net/wiki/Experience

const BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER  := preload("res://data/species/004_charmander.tres")
const TACKLE      := preload("res://data/moves/tackle.tres")

# ---- GrowthCurve: canonical Bulbapedia values at level 50 & 100 ----------

func test_growth_curves_at_level_50() -> void:
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_FAST, 50), 125_000, "Medium Fast L50")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_SLOW, 50), 117_360, "Medium Slow L50")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.FAST,        50), 100_000, "Fast L50")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.SLOW,        50), 156_250, "Slow L50")

func test_growth_curves_at_level_100() -> void:
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_FAST, 100), 1_000_000, "Medium Fast L100")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_SLOW, 100), 1_059_860, "Medium Slow L100")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.FAST,        100),   800_000, "Fast L100")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.SLOW,        100), 1_250_000, "Slow L100")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.ERRATIC,     100),   600_000, "Erratic L100")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.FLUCTUATING, 100), 1_640_000, "Fluctuating L100")

func test_growth_curves_clamp_negative_at_low_levels() -> void:
	# Medium Slow formula dips negative at L1 — must clamp to 0.
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_SLOW, 1), 0, "Medium Slow L1")
	assert_eq(GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_FAST, 1), 0, "Medium Fast L1 is also 0 (level 1 start)")

func test_level_for_exp_roundtrip() -> void:
	# If a Pokémon has exactly the threshold XP for L50, level_for_exp returns 50.
	var xp_l50 := GrowthCurve.total_exp_at(Enums.GrowthRate.MEDIUM_SLOW, 50)
	assert_eq(GrowthCurve.level_for_exp(Enums.GrowthRate.MEDIUM_SLOW, xp_l50), 50)
	# One XP short → still L49.
	assert_eq(GrowthCurve.level_for_exp(Enums.GrowthRate.MEDIUM_SLOW, xp_l50 - 1), 49)


# ---- PokemonInstance.gain_exp --------------------------------------------

func _fresh_bulbasaur_l5() -> PokemonInstance:
	# Phase 1 setup: IVs=0, EVs=0, Hardy (neutral). Medium Slow curve.
	# L5 threshold = 135, L6 threshold = 179 → needs 44 XP to level up.
	# create() now seeds experience to the level's base threshold
	# automatically, so no manual set is required.
	return PokemonInstance.create(BULBASAUR, 5, [TACKLE])


func test_gain_exp_under_threshold_returns_empty() -> void:
	var b := _fresh_bulbasaur_l5()
	# Needs 44 XP to hit L6; 40 is under.
	var events := b.gain_exp(40)
	assert_eq(events.size(), 0, "no level-ups expected")
	assert_eq(b.level, 5, "level unchanged")
	assert_eq(b.experience, 135 + 40, "experience accumulated")


func test_gain_exp_single_level() -> void:
	var b := _fresh_bulbasaur_l5()
	# 44 XP = exactly the L6 threshold.
	var events := b.gain_exp(44)
	assert_eq(events.size(), 1, "one level-up expected")
	assert_eq(b.level, 6)
	assert_eq(events[0].old_level, 5)
	assert_eq(events[0].new_level, 6)


func test_gain_exp_multi_level() -> void:
	# L5 → L7 requires 44 (to L6) + 57 (to L7) = 101 XP.
	var b := _fresh_bulbasaur_l5()
	var events := b.gain_exp(200)  # well past L7 threshold
	assert_gte(events.size(), 2, "at least two level-ups expected")
	assert_eq(events[0].new_level, 6)
	assert_eq(events[1].new_level, 7)
	assert_gte(b.level, 7)


func test_level_up_event_stat_deltas_match_formula() -> void:
	var b := _fresh_bulbasaur_l5()
	var events := b.gain_exp(44)
	assert_eq(events.size(), 1)
	var e: LevelUpEvent = events[0]
	# Hand computed Bulbasaur (IVs=0 EVs=0 neutral) stats:
	# L5 → HP 19, Atk 9,  Def 9,  SpA 11, SpD 11, Spe 9
	# L6 → HP 21, Atk 10, Def 10, SpA 12, SpD 12, Spe 10
	assert_eq(int(e.old_stats["hp"]),  19)
	assert_eq(int(e.new_stats["hp"]),  21)
	assert_eq(int(e.stat_deltas["hp"]), 2)
	assert_eq(int(e.stat_deltas["atk"]), 1)
	assert_eq(int(e.stat_deltas["spa"]), 1)
	assert_eq(e.hp_delta, 2)


func test_hp_preserved_as_absolute_delta() -> void:
	# FR/LG rule: current HP gains the ABSOLUTE hp_delta on level-up.
	var b := _fresh_bulbasaur_l5()
	# Take 5 damage first. At L5 max_hp is 19, so current = 14.
	b.take_damage(5)
	assert_eq(b.current_hp, 14)
	# Gain enough to hit L6. hp_delta at L5→L6 should be 2.
	b.gain_exp(44)
	assert_eq(b.level, 6)
	assert_eq(b.max_hp(), 21)
	assert_eq(b.current_hp, 16, "14 + 2 (absolute delta), not 21 (full) or proportional")


func test_gain_exp_at_level_100_is_noop() -> void:
	var b := PokemonInstance.create(BULBASAUR, 100, [TACKLE])
	var xp_before := b.experience
	var events := b.gain_exp(9_999_999)
	assert_eq(events.size(), 0, "no level-ups at L100")
	assert_eq(b.level, 100, "level unchanged")
	assert_eq(b.experience, xp_before, "experience not mutated")


func test_exp_to_next_level() -> void:
	var b := _fresh_bulbasaur_l5()
	# L5 at exactly 135 XP; L6 threshold is 179 → need 44.
	assert_eq(b.exp_to_next_level(), 44)
	# At L100 → 0.
	var b100 := PokemonInstance.create(BULBASAUR, 100, [TACKLE])
	assert_eq(b100.exp_to_next_level(), 0)


# ---- XpFormula -----------------------------------------------------------

func test_xp_formula_wild_vs_trainer() -> void:
	# base_exp_yield = 62 in data/species/004_charmander.tres (PokéAPI
	# returns the current-gen value; Gen 3 canonically was 65, but PokéAPI
	# doesn't track past_values for base_experience).
	# At L10: wild = 62 * 10 / 7 = 88. Trainer = 88 * 3 / 2 = 132.
	var c := PokemonInstance.create(CHARMANDER, 10, [TACKLE])
	var base: int = CHARMANDER.base_exp_yield
	var wild := XpFormula.exp_for_kill(c, false)
	var trainer := XpFormula.exp_for_kill(c, true)
	assert_gt(trainer, wild, "trainer XP should exceed wild XP")
	assert_eq(wild, base * 10 / 7, "wild XP formula")
	assert_eq(trainer, (base * 10 / 7) * 3 / 2, "trainer XP formula")


func test_xp_formula_minimum_one() -> void:
	# Very low-level encounter: base_exp * level / 7 can floor to 0. Floor is 1.
	var c := PokemonInstance.create(CHARMANDER, 1, [TACKLE])
	var xp := XpFormula.exp_for_kill(c, false)
	assert_gte(xp, 1, "any valid kill yields at least 1 XP")
