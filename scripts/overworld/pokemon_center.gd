extends Node2D
## Phase 2d — Pokémon Center interior scene.
##
## Structure:
##   * Background: 240×160 TextureRect with the pre-cropped PC interior image.
##   * Walls + counter: static collision rectangles.
##   * Player: inherited Player.tscn, spawned at GameState.next_spawn cell.
##   * Nurse: Area2D in "blockers" group at (7, 2), runs heal dialog on A.
##   * ExitMat: Door in "doors" group at (7, 8), returns to Overworld.

func _ready() -> void:
	$Player.input_locked = true
	$Player.apply_spawn(GameState.next_spawn)
	GameState.next_spawn = {}
	await SceneFade.fade_in()
	$Player.input_locked = false
