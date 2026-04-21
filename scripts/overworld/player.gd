extends Node2D
## Grid-based player with per-tile tween, input lock during move, and
## collision against solid tiles on the parent's `Objects` TileMapLayer.

signal moved(new_cell: Vector2i)
signal party_screen_requested

const TILE_SIZE := 16

enum Dir { DOWN, UP, LEFT, RIGHT }

const DIR_VEC := {
	Dir.DOWN: Vector2i(0, 1),
	Dir.UP: Vector2i(0, -1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}
const DIR_NAMES := {
	Dir.DOWN: "down",
	Dir.UP: "up",
	Dir.LEFT: "left",
	Dir.RIGHT: "right",
}

@export var move_duration: float = 0.15
@export var start_cell: Vector2i = Vector2i(10, 7)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var cell: Vector2i
var facing: int = Dir.DOWN
var is_moving: bool = false
# When true, all input is ignored (e.g. during a battle overlay).
var input_locked: bool = false

# Looked up from the parent Overworld scene; holds the tiles we can't walk through.
var objects_layer: TileMapLayer

func _ready() -> void:
	cell = start_cell
	position = _cell_to_world(cell)

	var parent := get_parent()
	if parent and parent.has_node("Objects"):
		objects_layer = parent.get_node("Objects") as TileMapLayer

	sprite.play("idle_" + DIR_NAMES[facing])

func _process(_delta: float) -> void:
	if is_moving or input_locked:
		return
	var input_dir := _read_input()
	if input_dir == -1:
		sprite.play("idle_" + DIR_NAMES[facing])
		return

	# Always turn to face the input direction, even if blocked.
	facing = input_dir

	var target_cell: Vector2i = cell + DIR_VEC[facing]
	if _is_blocked(target_cell):
		# Bumped a wall — show idle facing the bump (animation placeholder for Phase 1).
		sprite.play("idle_" + DIR_NAMES[facing])
		return

	_tween_to(target_cell)

func _unhandled_input(event: InputEvent) -> void:
	if input_locked or is_moving:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		party_screen_requested.emit()
		get_viewport().set_input_as_handled()

func _read_input() -> int:
	# ui_up / ui_down / ui_left / ui_right are arrow-keys + d-pad by default in Godot 4.
	if Input.is_action_pressed("ui_down"):  return Dir.DOWN
	if Input.is_action_pressed("ui_up"):    return Dir.UP
	if Input.is_action_pressed("ui_left"):  return Dir.LEFT
	if Input.is_action_pressed("ui_right"): return Dir.RIGHT
	return -1

func _is_blocked(target_cell: Vector2i) -> bool:
	if objects_layer != null:
		var data := objects_layer.get_cell_tile_data(target_cell)
		if data and data.get_custom_data("solid"):
			return true
	# Dynamic blockers (trainers, NPCs). Each adds itself to the "blockers" group
	# and exposes a `cell: Vector2i` property.
	for b in get_tree().get_nodes_in_group("blockers"):
		if "cell" in b and b.cell == target_cell:
			return true
	return false

func _tween_to(target_cell: Vector2i) -> void:
	is_moving = true
	sprite.play("walk_" + DIR_NAMES[facing])
	var target_pos := _cell_to_world(target_cell)
	var tween := create_tween()
	tween.tween_property(self, "position", target_pos, move_duration)
	tween.tween_callback(_on_move_complete.bind(target_cell))

func _on_move_complete(target_cell: Vector2i) -> void:
	cell = target_cell
	is_moving = false
	moved.emit(cell)
	# If the key is released, _process() will snap to idle on the next frame;
	# if still held, it will immediately schedule the next step.

func _cell_to_world(c: Vector2i) -> Vector2:
	# Center the sprite in the tile (tile origin is top-left corner).
	return Vector2(c.x * TILE_SIZE + TILE_SIZE / 2, c.y * TILE_SIZE + TILE_SIZE / 2)
