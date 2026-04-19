class_name Species
extends Resource
## Immutable template for a Pokémon species. One .tres file per species.
##
## Phase 1 uses dex_number, name, types, base_stats, catch_rate, base_exp_yield,
## growth_rate, learnset, front_sprite, back_sprite. Evolutions and abilities
## are reserved for Phase 2+ but the fields are present so we don't have to
## schema-migrate later.

@export var dex_number: int = 0
@export var species_name: String = ""         # Renamed to avoid shadowing Resource.name in older Godot builds.
@export var types: Array[int] = []            # Enums.Type values. One or two entries.
@export var base_stats: Dictionary = {        # keys: hp, atk, def, spa, spd, spe
	"hp": 1, "atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1,
}
@export var catch_rate: int = 255             # 3 = legendary, 255 = super common
@export var base_exp_yield: int = 0           # Gen 3+ formula
@export var growth_rate: int = 0              # Enums.GrowthRate
@export var learnset: Array[Dictionary] = []  # [{level: int, move_id: String}]

# Visuals.
@export var front_sprite: Texture2D
@export var back_sprite: Texture2D

# Reserved for later phases — leave empty in Phase 1 .tres files.
@export var evolutions: Array[Dictionary] = []  # [{method, param, into_dex}]
@export var abilities: Array[String] = []
