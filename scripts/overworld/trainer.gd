extends Node2D
## A stationary NPC trainer that watches a sight cone for the player.
##
## The overworld bootstrap polls each trainer's `sees_player()` after every
## player step and calls `_spot_trainer(t)` directly when the sightline is
## broken. No signal — the poll-based path is simpler and matches the rest
## of the overworld's state handling.

# Must be unique across the game (used as the key in GameState.defeated_trainers).
@export var trainer_id: String = "trainer_001"

# How many tiles ahead the trainer can see.
@export_range(1, 10) var sight_tiles: int = 3

# Facing direction — values come from Direction.DOWN/UP/LEFT/RIGHT.
@export_enum("down:0", "up:1", "left:2", "right:3") var facing: int = 0

# Ordered team the trainer brings into battle (Phase 2c: up to 6). Assign
# an inline sub-resource or a .tres via the inspector.
@export var team: TrainerTeam

# Tile the trainer stands on. Set this so the overworld controller and the
# sightline check agree on the trainer's grid position. (16-px tiles.)
@export var cell: Vector2i = Vector2i.ZERO

const TILE_SIZE := 16

@onready var sprite: Sprite2D = $Sprite2D
@onready var alert: Sprite2D = $AlertBubble

const NPC_SHEET := preload("res://assets/sprites/trainers/frlg/npc_007.png")

# Column in the 13-col NPC strip for each facing direction (stand pose).
# 0=down(SS)=col1, 1=up(SN)=col4, 2=left(SW)=col7, 3=right(SE)=col10.
const FACING_COL := {0: 1, 1: 4, 2: 7, 3: 10}

var TRAINER_TEX: Dictionary

func _make_atlas(col: int) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = NPC_SHEET
	t.region = Rect2(col * 16, 0, 16, 24)
	return t

func _ready() -> void:
	TRAINER_TEX = {
		0: _make_atlas(FACING_COL[0]),
		1: _make_atlas(FACING_COL[1]),
		2: _make_atlas(FACING_COL[2]),
		3: _make_atlas(FACING_COL[3]),
	}
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

## Build the full team this trainer brings into battle. Called by the
## overworld after the player enters sightline. Returns [] if the team
## is null or empty (push_error already alerts).
func build_team() -> Array[PokemonInstance]:
	if team == null or team.entries.is_empty():
		push_error("Trainer %s has no team configured." % trainer_id)
		return []
	return team.build_instances()
