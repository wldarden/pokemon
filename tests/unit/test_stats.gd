extends GutTest
## Validates PokemonInstance stat formulas (Gen 3 FR/LG).
## Reference: https://bulbapedia.bulbagarden.net/wiki/Stat

const BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER  := preload("res://data/species/004_charmander.tres")
const SQUIRTLE    := preload("res://data/species/007_squirtle.tres")


func test_species_resources_loaded() -> void:
	assert_not_null(BULBASAUR, "Bulbasaur .tres must load")
	assert_eq(BULBASAUR.dex_number, 1)
	assert_eq(BULBASAUR.species_name, "Bulbasaur")
	assert_eq(BULBASAUR.types.size(), 2)
	assert_eq(BULBASAUR.types[0], Enums.Type.GRASS)
	assert_eq(BULBASAUR.types[1], Enums.Type.POISON)
	assert_eq(int(BULBASAUR.base_stats["hp"]), 45)


func test_bulbasaur_level5_stats_match_gen3_formula() -> void:
	# At L5 with IV=0, EV=0, neutral nature:
	#   HP    = floor((2*base) * 5 / 100) + 5 + 10
	#   other = floor(floor((2*base) * 5 / 100) + 5)
	var b := PokemonInstance.create(BULBASAUR, 5)
	assert_eq(b.level, 5)
	assert_eq(b.max_hp(), (2 * 45) * 5 / 100 + 5 + 10, "HP")  # 4 + 15 = 19
	assert_eq(b.stat(Enums.StatKey.ATTACK),     (2 * 49) * 5 / 100 + 5, "Atk")   # 4 + 5 = 9
	assert_eq(b.stat(Enums.StatKey.DEFENSE),    (2 * 49) * 5 / 100 + 5, "Def")   # 4 + 5 = 9
	assert_eq(b.stat(Enums.StatKey.SP_ATTACK),  (2 * 65) * 5 / 100 + 5, "SpA")   # 6 + 5 = 11
	assert_eq(b.stat(Enums.StatKey.SP_DEFENSE), (2 * 65) * 5 / 100 + 5, "SpD")   # 6 + 5 = 11
	assert_eq(b.stat(Enums.StatKey.SPEED),      (2 * 45) * 5 / 100 + 5, "Spe")   # 4 + 5 = 9


func test_bulbasaur_level50_stats_match_gen3_formula() -> void:
	var b := PokemonInstance.create(BULBASAUR, 50)
	assert_eq(b.max_hp(), (2 * 45) * 50 / 100 + 50 + 10, "HP")  # 45 + 60 = 105
	assert_eq(b.stat(Enums.StatKey.SP_ATTACK), (2 * 65) * 50 / 100 + 5, "SpA")  # 65 + 5 = 70


func test_current_hp_starts_at_max() -> void:
	var c := PokemonInstance.create(CHARMANDER, 10)
	assert_eq(c.current_hp, c.max_hp())
	assert_false(c.is_fainted())


func test_take_damage_clamps_to_zero_and_reports_fainted() -> void:
	var s := PokemonInstance.create(SQUIRTLE, 5)
	var hp_before := s.current_hp
	var lost := s.take_damage(9999)
	assert_eq(s.current_hp, 0)
	assert_eq(lost, hp_before)
	assert_true(s.is_fainted())


func test_neutral_nature_no_stat_change() -> void:
	var b := PokemonInstance.create(BULBASAUR, 50)
	b.nature = Enums.Nature.HARDY  # neutral
	# HARDY affects nothing, so the stat matches the un-nature'd formula.
	assert_eq(b.stat(Enums.StatKey.ATTACK), (2 * 49) * 50 / 100 + 5)


func test_modest_nature_boosts_spa_reduces_atk() -> void:
	var b := PokemonInstance.create(BULBASAUR, 50)
	b.nature = Enums.Nature.MODEST  # +SpA -Atk
	var neutral_spa := (2 * 65) * 50 / 100 + 5
	var neutral_atk := (2 * 49) * 50 / 100 + 5
	assert_eq(b.stat(Enums.StatKey.SP_ATTACK), int(floor(neutral_spa * 1.1)))
	assert_eq(b.stat(Enums.StatKey.ATTACK),    int(floor(neutral_atk * 0.9)))
	# Unaffected stats unchanged.
	assert_eq(b.stat(Enums.StatKey.DEFENSE),   (2 * 49) * 50 / 100 + 5)
