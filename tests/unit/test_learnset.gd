extends GutTest
## Phase 2b: LearnsetResolver and already_knows predicate.
## Uses the real Bulbasaur .tres learnset populated from PokéAPI.

const BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER  := preload("res://data/species/004_charmander.tres")
const SQUIRTLE    := preload("res://data/species/007_squirtle.tres")

const TACKLE      := preload("res://data/moves/tackle.tres")
const VINE_WHIP   := preload("res://data/moves/vine_whip.tres")


func test_bulbasaur_learns_leech_seed_at_l7() -> void:
	var moves := LearnsetResolver.moves_learned_at(BULBASAUR, 7)
	assert_eq(moves.size(), 1)
	assert_eq(moves[0].move_name, "Leech Seed")


func test_bulbasaur_learns_vine_whip_at_l10() -> void:
	var moves := LearnsetResolver.moves_learned_at(BULBASAUR, 10)
	assert_eq(moves.size(), 1)
	assert_eq(moves[0].move_name, "Vine Whip")


func test_bulbasaur_learns_two_moves_at_l15() -> void:
	# Gen 3 Bulbasaur learns BOTH Poison Powder and Sleep Powder at L15.
	var moves := LearnsetResolver.moves_learned_at(BULBASAUR, 15)
	assert_eq(moves.size(), 2, "expected 2 moves learned at L15")
	var names := []
	for m in moves:
		names.append(m.move_name)
	# Order is sorted by move name, but either way both should be present.
	assert_has(names, "Poison Powder")
	assert_has(names, "Sleep Powder")


func test_no_moves_at_unused_level() -> void:
	# L2 is not in Bulbasaur's learnset.
	var moves := LearnsetResolver.moves_learned_at(BULBASAUR, 2)
	assert_eq(moves.size(), 0)


func test_null_species_returns_empty() -> void:
	var moves := LearnsetResolver.moves_learned_at(null, 5)
	assert_eq(moves.size(), 0)


func test_already_knows_true_when_slot_exists() -> void:
	var b := PokemonInstance.create(BULBASAUR, 5, [TACKLE, VINE_WHIP])
	assert_true(LearnsetResolver.already_knows(b, TACKLE))
	assert_true(LearnsetResolver.already_knows(b, VINE_WHIP))


func test_already_knows_false_when_not_in_moveset() -> void:
	var b := PokemonInstance.create(BULBASAUR, 5, [TACKLE])
	assert_false(LearnsetResolver.already_knows(b, VINE_WHIP))


func test_already_knows_handles_null_inputs() -> void:
	var b := PokemonInstance.create(BULBASAUR, 5, [TACKLE])
	assert_false(LearnsetResolver.already_knows(null, TACKLE))
	assert_false(LearnsetResolver.already_knows(b, null))


func test_all_three_starters_have_populated_learnsets() -> void:
	# Sanity check: the fetch script populated all 3 species.
	assert_gt(BULBASAUR.learnset.size(), 0, "Bulbasaur learnset populated")
	assert_gt(CHARMANDER.learnset.size(), 0, "Charmander learnset populated")
	assert_gt(SQUIRTLE.learnset.size(), 0, "Squirtle learnset populated")
