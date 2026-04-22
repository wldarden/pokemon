extends GutTest
## Phase 2d — heal_party, Player.apply_spawn, DialogSequence builder.

const BULBASAUR      := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER     := preload("res://data/species/004_charmander.tres")
const TACKLE         := preload("res://data/moves/tackle.tres")

# Preload to work around Godot 4.6 class_name parsing in headless tests.
# This makes DialogSequence available as a global class in the test file.
const DialogSequence := preload("res://scripts/overworld/dialog_sequence.gd")

# ---- GameState.heal_party ------------------------------------------------

func _make_damaged_mon() -> PokemonInstance:
	var m := PokemonInstance.create(BULBASAUR, 10, [TACKLE])
	m.current_hp = 1
	m.status = Enums.StatusCondition.BURN
	m.moves[0].pp_current = 0
	return m

func test_heal_party_restores_hp_to_max() -> void:
	var a := _make_damaged_mon()
	var b := PokemonInstance.create(CHARMANDER, 8, [TACKLE])
	b.current_hp = 0   # fainted
	GameState.player_party = [a, b]
	GameState.heal_party()
	assert_eq(a.current_hp, a.max_hp(), "damaged mon at full")
	assert_eq(b.current_hp, b.max_hp(), "fainted mon revived")

func test_heal_party_clears_status() -> void:
	var a := _make_damaged_mon()
	GameState.player_party = [a]
	GameState.heal_party()
	assert_eq(a.status, Enums.StatusCondition.NONE, "status cleared to NONE")

func test_heal_party_restores_pp() -> void:
	var a := _make_damaged_mon()
	GameState.player_party = [a]
	GameState.heal_party()
	assert_eq(a.moves[0].pp_current, a.moves[0].move.pp, "PP restored to max")

func test_heal_party_empty_is_noop() -> void:
	GameState.player_party = []
	GameState.heal_party()   # must not crash
	assert_eq(GameState.player_party.size(), 0)

# ---- DialogSequence builder ----------------------------------------------

func test_dialog_sequence_builder_accumulates_steps() -> void:
	# Uses the DialogSequence preload alias (declared at the top of this file) because
	# bare `DialogSequence.new()` fails to parse under GUT's headless runner
	# for newly-added class_name classes. Proven pattern from Phase 2c.
	var seq = DialogSequence.new() \
		.say("hello") \
		.wait(0.5) \
		.say("world")
	assert_eq(seq.size(), 3, "three steps queued")

# ---- Player.apply_spawn --------------------------------------------------

func test_player_apply_spawn_sets_cell_and_facing() -> void:
	# Player.apply_spawn mutates internal vars only — no scene tree needed.
	const PlayerScript := preload("res://scripts/overworld/player.gd")
	var p: Node2D = PlayerScript.new()
	p.apply_spawn({"cell": Vector2i(5, 5), "facing": Direction.UP})
	assert_eq(p.cell, Vector2i(5, 5))
	assert_eq(p.facing, Direction.UP)
	p.free()
