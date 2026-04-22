class_name Door
extends Area2D
## Phase 2d — scene-transition trigger. Place on a cell in the "doors"
## group. When the player's move completes on that cell, Player invokes
## `on_enter(player)`, which fades out and swaps to `target_scene`.
##
## The receiving scene's _ready() reads GameState.next_spawn to place
## the player at `target_cell` facing `target_facing`.

## Where this door lives on its own map. Compared with player.cell.
@export var cell: Vector2i = Vector2i.ZERO

## PackedScene to swap into when the player enters this cell.
@export var target_scene: PackedScene

## Where the player should appear in the target scene.
@export var target_cell: Vector2i = Vector2i.ZERO

## Facing direction in the target scene (Direction enum values 0..3).
@export_enum("down:0", "up:1", "left:2", "right:3") var target_facing: int = 0

func _ready() -> void:
	add_to_group("doors")

## Called by Player._on_move_complete when the player steps onto `cell`.
## Fades the screen, sets GameState.next_spawn, and triggers the swap.
func on_enter(_player: Node) -> void:
	if target_scene == null:
		push_error("Door at %s has no target_scene." % cell)
		return
	GameState.next_spawn = {
		"scene": target_scene,
		"cell": target_cell,
		"facing": target_facing,
	}
	await SceneFade.fade_out()
	get_tree().change_scene_to_packed(target_scene)
