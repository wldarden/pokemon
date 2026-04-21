extends GutTest
## Phase 2c — party helpers, XP split, TrainerTeam construction.

const BULBASAUR  := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER := preload("res://data/species/004_charmander.tres")
const SQUIRTLE   := preload("res://data/species/007_squirtle.tres")
const TACKLE     := preload("res://data/moves/tackle.tres")

# GUT's headless parser can't resolve `TrainerTeam.new()` from `class_name`
# registration alone for newly-added Resource classes — removing this
# preload causes the whole file to silently fail to load, dropping all 12
# tests. Other class_names (PartyHelpers, XpFormula, etc.) work bare here
# because the suite only uses them via static calls.
const TrainerTeam := preload("res://scripts/data/trainer_team.gd")

# ---- XpFormula.split_among_participants ----------------------------------

func test_xp_split_even() -> void:
	assert_eq(XpFormula.split_among_participants(30, 3), 10, "30/3 = 10 exact")

func test_xp_split_floors_remainder() -> void:
	# FR/LG rule: remainder is discarded, each participant gets the floor.
	assert_eq(XpFormula.split_among_participants(10, 3), 3, "10/3 floor = 3")

func test_xp_split_min_one_when_total_positive() -> void:
	# 1 XP across 3 participants would floor to 0; clamp to 1 so nobody gets
	# skipped when there's any XP to hand out.
	assert_eq(XpFormula.split_among_participants(1, 3), 1, "min-1 clamp")

func test_xp_split_zero_total_gives_zero() -> void:
	# No XP → no one gets any. The min-1 clamp only kicks in when total > 0.
	assert_eq(XpFormula.split_among_participants(0, 3), 0, "0 total → 0 each")

func test_xp_split_single_participant_full_share() -> void:
	assert_eq(XpFormula.split_among_participants(50, 1), 50, "all to sole participant")


# ---- PartyHelpers --------------------------------------------------------

func _make_mon(species: Species, lvl: int = 5, hp_fraction: float = 1.0) -> PokemonInstance:
	var m := PokemonInstance.create(species, lvl, [TACKLE])
	m.current_hp = int(m.max_hp() * hp_fraction)
	return m

func _fainted(species: Species) -> PokemonInstance:
	var m := _make_mon(species, 5, 0.0)
	m.current_hp = 0
	return m

func test_first_non_fainted_picks_second_slot() -> void:
	var party := [_fainted(BULBASAUR), _make_mon(CHARMANDER), _make_mon(SQUIRTLE)]
	assert_eq(PartyHelpers.first_non_fainted(party), 1)

func test_first_non_fainted_returns_minus_one_when_all_fainted() -> void:
	var party := [_fainted(BULBASAUR), _fainted(CHARMANDER)]
	assert_eq(PartyHelpers.first_non_fainted(party), -1, "team wipe signal")

func test_all_fainted_true_on_wipe() -> void:
	var party := [_fainted(BULBASAUR), _fainted(CHARMANDER)]
	assert_true(PartyHelpers.all_fainted(party))

func test_all_fainted_false_with_alive_member() -> void:
	var party := [_fainted(BULBASAUR), _make_mon(CHARMANDER)]
	assert_false(PartyHelpers.all_fainted(party))

func test_can_switch_to_valid_slot() -> void:
	var party := [_make_mon(BULBASAUR), _make_mon(CHARMANDER), _fainted(SQUIRTLE)]
	# From active=0, slot 1 is valid (alive, non-active).
	assert_true(PartyHelpers.can_switch_to(party, 1, 0), "alive non-active slot")
	# Cannot switch to self (active slot).
	assert_false(PartyHelpers.can_switch_to(party, 0, 0), "can't switch to active")
	# Cannot switch to fainted.
	assert_false(PartyHelpers.can_switch_to(party, 2, 0), "can't switch to fainted")


# ---- TrainerTeam ---------------------------------------------------------

func test_trainer_team_builds_instances_with_default_moves() -> void:
	var team := TrainerTeam.new()
	team.entries = [
		{"species": BULBASAUR, "level": 5},
		{"species": CHARMANDER, "level": 7},
		{"species": SQUIRTLE, "level": 6},
	]
	var mons: Array = team.build_instances()
	assert_eq(mons.size(), 3, "3 entries → 3 instances")
	assert_eq(mons[0].species.dex_number, 1, "slot 0 = Bulbasaur")
	assert_eq(mons[0].level, 5, "slot 0 level")
	assert_eq(mons[1].species.dex_number, 4, "slot 1 = Charmander")
	assert_eq(mons[1].level, 7, "slot 1 level")
	# Empty moves → DefaultMovesets fallback (Bulbasaur's first default move is TACKLE).
	assert_gt(mons[0].moves.size(), 0, "default movesets populated")

func test_trainer_team_honors_explicit_moves() -> void:
	var team := TrainerTeam.new()
	team.entries = [
		{"species": BULBASAUR, "level": 5, "moves": [TACKLE]},
	]
	var mons: Array = team.build_instances()
	assert_eq(mons[0].moves.size(), 1, "explicit moves used verbatim")
	assert_eq(mons[0].moves[0].move, TACKLE, "TACKLE was the supplied move")
