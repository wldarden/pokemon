extends Node2D
## Step 2 bootstrap: paints a 20x15 test map procedurally onto two layers.
##   Ground   — grass + path + encounter grass (walkable decorations)
##   Objects  — transparent-alpha bushes and trees (solid blockers)

const MAP_W := 20
const MAP_H := 15
const SOURCE_ID := 0  # single TileSetAtlasSource in overworld.tres

# Atlas coords — must match tiles defined in assets/tilesets/overworld.tres
const GRASS        := Vector2i(0, 0)
const GRASS_TUFT   := Vector2i(1, 0)   # has tall_grass=true custom data
# Path 3x3 autotile (corners + edges + center)
const PATH_TL := Vector2i(0, 1); const PATH_TM := Vector2i(1, 1); const PATH_TR := Vector2i(2, 1)
const PATH_ML := Vector2i(0, 2); const PATH_MM := Vector2i(1, 2); const PATH_MR := Vector2i(2, 2)
const PATH_BL := Vector2i(0, 3); const PATH_BM := Vector2i(1, 3); const PATH_BR := Vector2i(2, 3)
# Objects
const BUSH     := Vector2i(5, 0)   # solid=true
const TREE_TOP := Vector2i(4, 0)   # decorative
const TREE_BOT := Vector2i(4, 1)   # solid=true

# Path runs horizontally, 3 tiles thick, centered vertically (rows 6-8).
const PATH_Y_TOP := 6
const PATH_Y_BOT := 8
const PATH_X_LEFT  := 1
const PATH_X_RIGHT := MAP_W - 2

# Encounter grass patch — upper-right area (shrunk a bit to avoid path/border overlap).
const ENCOUNTER_RECT := Rect2i(12, 2, 5, 4)  # x=12..16, y=2..5

@onready var ground: TileMapLayer = $Ground
@onready var objects: TileMapLayer = $Objects
@onready var overhead: TileMapLayer = $Overhead
@onready var player: Node2D = $Player
@onready var encounter_zone: EncounterZone = $EncounterZone
@onready var trainers_root: Node = $Trainers

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const TYPE_CHART := preload("res://data/type_chart.tres")
const BULBASAUR := preload("res://data/species/001_bulbasaur.tres")
const TACKLE := preload("res://data/moves/tackle.tres")
const VINE_WHIP := preload("res://data/moves/vine_whip.tres")

var _current_battle: Node = null
var _spot_in_progress: bool = false

func _ready() -> void:
	_paint_ground()
	_paint_objects()
	_init_default_party_if_empty()
	encounter_zone.wild_encounter_triggered.connect(_on_wild_encounter)
	player.moved.connect(_on_player_moved_trainer_check)

func _init_default_party_if_empty() -> void:
	# Phase 1 shortcut: give the player a starter Bulbasaur if the party is
	# empty. Phase 4+ will replace this with a proper starter-choice flow.
	if not GameState.player_party.is_empty():
		return
	var starter := PokemonInstance.create(BULBASAUR, 5, [TACKLE, VINE_WHIP])
	GameState.player_party = [starter]

func _on_wild_encounter(species: Species, level: int) -> void:
	# Guard against a second overlay starting before the first one finishes.
	if _current_battle != null:
		return
	var wild_moves: Array[Move] = DefaultMovesets.for_species(species.dex_number)
	var wild_mon := PokemonInstance.create(species, level, wild_moves)

	player.input_locked = true

	_current_battle = BATTLE_SCENE.instantiate()
	add_child(_current_battle)
	_current_battle.battle_ended.connect(_on_battle_ended)

	var ctx := BattleContext.with_chart(TYPE_CHART)
	_current_battle.start(GameState.player_party, [wild_mon], ctx)

func _on_battle_ended(_result: BattleResult) -> void:
	if _current_battle:
		_current_battle.queue_free()
		_current_battle = null
	player.input_locked = false

# ---- Trainer sightline + spot sequence ------------------------------------

func _on_player_moved_trainer_check(player_cell: Vector2i) -> void:
	if _current_battle != null or _spot_in_progress:
		return
	for t in trainers_root.get_children():
		if not t.has_method("sees_player"):
			continue
		if t.sees_player(player_cell):
			_spot_trainer(t)
			return

func _spot_trainer(trainer: Node) -> void:
	_spot_in_progress = true
	player.input_locked = true
	await trainer.play_alert()
	# In Phase 1 we skip the "trainer walks to player" animation; just go
	# straight into the battle after the alert pop.
	_start_trainer_battle(trainer)
	_spot_in_progress = false

func _start_trainer_battle(trainer: Node) -> void:
	if _current_battle != null:
		return
	var opponent: PokemonInstance = trainer.build_opponent()

	_current_battle = BATTLE_SCENE.instantiate()
	add_child(_current_battle)
	_current_battle.battle_ended.connect(func(result): _on_trainer_battle_ended(result, trainer))

	var ctx := BattleContext.with_chart(TYPE_CHART)
	ctx.is_trainer = true
	_current_battle.start(GameState.player_party, [opponent], ctx)

func _on_trainer_battle_ended(result: BattleResult, trainer: Node) -> void:
	if result.outcome == BattleResult.Outcome.WIN:
		trainer.mark_defeated()
	_on_battle_ended(result)

func _paint_ground() -> void:
	for y in MAP_H:
		for x in MAP_W:
			ground.set_cell(Vector2i(x, y), SOURCE_ID, GRASS)

	# Encounter (tall-grass) patch.
	for y in range(ENCOUNTER_RECT.position.y, ENCOUNTER_RECT.end.y):
		for x in range(ENCOUNTER_RECT.position.x, ENCOUNTER_RECT.end.x):
			ground.set_cell(Vector2i(x, y), SOURCE_ID, GRASS_TUFT)

	# 3-tile-thick horizontal path across the middle.
	for x in range(PATH_X_LEFT, PATH_X_RIGHT + 1):
		var left := x == PATH_X_LEFT
		var right := x == PATH_X_RIGHT
		var top_tile    := PATH_TL if left else (PATH_TR if right else PATH_TM)
		var middle_tile := PATH_ML if left else (PATH_MR if right else PATH_MM)
		var bottom_tile := PATH_BL if left else (PATH_BR if right else PATH_BM)
		ground.set_cell(Vector2i(x, PATH_Y_TOP), SOURCE_ID, top_tile)
		ground.set_cell(Vector2i(x, PATH_Y_TOP + 1), SOURCE_ID, middle_tile)
		ground.set_cell(Vector2i(x, PATH_Y_BOT), SOURCE_ID, bottom_tile)

func _paint_objects() -> void:
	# Bush border (hedge) around the entire map.
	for x in MAP_W:
		objects.set_cell(Vector2i(x, 0), SOURCE_ID, BUSH)
		objects.set_cell(Vector2i(x, MAP_H - 1), SOURCE_ID, BUSH)
	for y in range(1, MAP_H - 1):
		objects.set_cell(Vector2i(0, y), SOURCE_ID, BUSH)
		objects.set_cell(Vector2i(MAP_W - 1, y), SOURCE_ID, BUSH)

	# A couple of decorative 2-tile trees in the interior, clear of the path.
	# tree_top goes on the Overhead layer so it renders OVER the player when they
	# stand on that cell (the tile is non-solid). tree_bot is a solid blocker,
	# stays on Objects (drawn under the player, which is fine because the player
	# can never stand on a blocker cell anyway).
	for tree_base in [Vector2i(4, 3), Vector2i(8, 11), Vector2i(17, 11)]:
		overhead.set_cell(tree_base + Vector2i(0, -1), SOURCE_ID, TREE_TOP)
		objects.set_cell(tree_base, SOURCE_ID, TREE_BOT)

	# A scattered single-tile bush or two.
	for b in [Vector2i(3, 10), Vector2i(11, 12)]:
		objects.set_cell(b, SOURCE_ID, BUSH)
