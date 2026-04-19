extends Node2D
## Step 5 checkpoint scene. Hardcodes a Bulbasaur vs Charmander battle so we
## can verify the layout in isolation, without needing an overworld encounter.
##
## Run as the main scene (or open and press F6) to see the battle layout.

const BULBASAUR   := preload("res://data/species/001_bulbasaur.tres")
const CHARMANDER  := preload("res://data/species/004_charmander.tres")
const TACKLE      := preload("res://data/moves/tackle.tres")
const VINE_WHIP   := preload("res://data/moves/vine_whip.tres")
const EMBER       := preload("res://data/moves/ember.tres")
const SCRATCH     := preload("res://data/moves/scratch.tres")
const TYPE_CHART  := preload("res://data/type_chart.tres")
const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")


func _ready() -> void:
	# Hardcoded pair — reproduces the test matchup from test_damage_calc.gd.
	var player_mon := PokemonInstance.create(BULBASAUR, 5, [TACKLE, VINE_WHIP])
	var enemy_mon := PokemonInstance.create(CHARMANDER, 5, [SCRATCH, EMBER])

	# Instance the Battle scene as a child and start it.
	var battle: Node = BATTLE_SCENE.instantiate()
	add_child(battle)
	battle.battle_ended.connect(_on_battle_ended)
	battle.start([player_mon], [enemy_mon], BattleContext.with_chart(TYPE_CHART))


func _on_battle_ended(result: BattleResult) -> void:
	print("Battle ended, outcome=%d, xp=%d" % [result.outcome, result.xp_gained])
