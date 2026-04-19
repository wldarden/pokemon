class_name EncounterZone
extends Node
## Watches the player's movements and rolls wild-encounter chances when they
## step onto a tile with the `tall_grass` custom-data flag.
##
## Usage: add this node to the Overworld scene; set `player_path` and
## `ground_layer_path`; configure `species_pool`, `encounter_rate`, levels.
## Hook up the `wild_encounter_triggered` signal in the overworld controller.

signal wild_encounter_triggered(species: Species, level: int)

## Species that can appear in this zone. All entries are equally weighted for
## Phase 1 — weighted pools and biome splits come later.
@export var species_pool: Array[Species] = []

@export_range(1, 100) var level_min: int = 2
@export_range(1, 100) var level_max: int = 5

## Probability of a wild encounter on each step into tall grass. 0.1 = 10%.
@export_range(0.0, 1.0, 0.01) var encounter_rate: float = 0.1

## Paths resolved relative to the scene root (Overworld).
@export var player_path: NodePath
@export var ground_layer_path: NodePath

var _rng: RandomNumberGenerator
var _ground: TileMapLayer

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	var player_node := get_node_or_null(player_path)
	if player_node and player_node.has_signal("moved"):
		player_node.moved.connect(_on_player_moved)

	_ground = get_node_or_null(ground_layer_path) as TileMapLayer

func _on_player_moved(cell: Vector2i) -> void:
	if _ground == null or species_pool.is_empty():
		return
	var tile_data := _ground.get_cell_tile_data(cell)
	if tile_data == null:
		return
	if not tile_data.get_custom_data("tall_grass"):
		return
	if _rng.randf() > encounter_rate:
		return

	var species: Species = species_pool[_rng.randi_range(0, species_pool.size() - 1)]
	var level: int = _rng.randi_range(level_min, level_max)
	wild_encounter_triggered.emit(species, level)
