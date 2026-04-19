extends Node2D
## A stationary NPC trainer that watches a sight cone for the player.
##
## Emits `trainer_triggered(trainer_id, opponent_species, level, moves)` when
## the player steps into the sight cone and the trainer hasn't been defeated.
## The overworld scene listens and launches a trainer battle.

signal trainer_triggered(trainer_id: String, opponent_species: Species, level: int, moves: Array)

# Must be unique across the game (used as the key in GameState.defeated_trainers).
@export var trainer_id: String = "trainer_001"

# How many tiles ahead the trainer can see.
@export_range(1, 10) var sight_tiles: int = 3

# Facing direction — values come from Direction.DOWN/UP/LEFT/RIGHT.
@export_enum("down:0", "up:1", "left:2", "right:3") var facing: int = 0

# The single Pokémon this trainer sends out (Phase 1: teams of 1).
@export var opponent_species: Species
@export_range(1, 100) var opponent_level: int = 5

# Tile the trainer stands on. Set this so the overworld controller and the
# sightline check agree on the trainer's grid position. (16-px tiles.)
@export var cell: Vector2i = Vector2i.ZERO

const TILE_SIZE := 16

@onready var sprite: Sprite2D = $Sprite2D
@onready var alert: Sprite2D = $AlertBubble

const TRAINER_TEX := {
	0: preload("res://assets/sprites/trainers/trainer_down.png"),
	1: preload("res://assets/sprites/trainers/trainer_up.png"),
	2: preload("res://assets/sprites/trainers/trainer_left.png"),
	3: preload("res://assets/sprites/trainers/trainer_right.png"),
}

func _ready() -> void:
	# Snap to the configured cell.
	position = Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)
	sprite.texture = TRAINER_TEX[facing]
	alert.visible = false
	add_to_group("blockers")  # picked up by Player._is_blocked()

## Called by the overworld controller after each player step.
## Returns true if the player is in this trainer's sight cone AND the trainer
## has not been defeated yet.
func sees_player(player_cell: Vector2i) -> bool:
	if GameState.defeated_trainers.get(trainer_id, false):
		return false
	var delta := player_cell - cell
	var step := Direction.vec(facing)
	for i in range(1, sight_tiles + 1):
		if delta == step * i:
			return true
	return false

## Shows the "!" bubble over the trainer for a brief moment, then returns.
## Called by the overworld controller in the spot sequence.
func play_alert() -> void:
	alert.visible = true
	# Short pop animation: tween scale up then back down.
	alert.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(alert, "scale", Vector2(1.0, 1.0), 0.12)
	tw.tween_interval(0.6)
	await tw.finished

func mark_defeated() -> void:
	GameState.defeated_trainers[trainer_id] = true

## Build the Pokémon this trainer sends out. Called by the overworld after
## the player enters sightline.
func build_opponent() -> PokemonInstance:
	var moves: Array[Move] = DefaultMovesets.for_species(opponent_species.dex_number)
	return PokemonInstance.create(opponent_species, opponent_level, moves)
