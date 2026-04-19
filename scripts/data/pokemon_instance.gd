class_name PokemonInstance
extends RefCounted
## A runtime Pokémon. NOT a Resource — this holds mutating state (HP, PP, XP,
## status) and is meant to be created from an immutable Species template.
##
## Stat formulas: Gen 3 (FireRed/LeafGreen). See Bulbapedia "Stat" page.
##     HP    = floor((2*base + IV + floor(EV/4)) * level / 100) + level + 10
##     Other = floor(floor((2*base + IV + floor(EV/4)) * level / 100 + 5) * nature)
##   where nature is 1.1 (boosted), 1.0 (neutral), or 0.9 (hindered).

var species: Species
var nickname: String = ""
var level: int = 1
var experience: int = 0

# IVs 0-31, EVs 0-252 per stat, 510 total across all stats (Gen 3 cap).
var ivs: Dictionary = {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
var evs: Dictionary = {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
var nature: int = Enums.Nature.HARDY  # neutral
var ability: String = ""              # Phase 2+

var moves: Array[MoveSlot] = []       # max 4

var current_hp: int = 0
var status: int = Enums.StatusCondition.NONE
var held_item: String = ""            # Phase 2+

# Map StatKey enum → base_stats dict key.
const _STAT_KEY_NAMES := {
	Enums.StatKey.HP: "hp",
	Enums.StatKey.ATTACK: "atk",
	Enums.StatKey.DEFENSE: "def",
	Enums.StatKey.SP_ATTACK: "spa",
	Enums.StatKey.SP_DEFENSE: "spd",
	Enums.StatKey.SPEED: "spe",
}

static func create(p_species: Species, p_level: int, p_moves: Array = []) -> PokemonInstance:
	var p := PokemonInstance.new()
	p.species = p_species
	p.level = p_level
	for m in p_moves:
		p.moves.append(MoveSlot.from_move(m))
	p.current_hp = p.max_hp()
	return p

## Returns the effective value of a stat using the Gen 3 formula.
## `stat` is an Enums.StatKey value.
func stat(stat_key: int) -> int:
	var name: String = _STAT_KEY_NAMES[stat_key]
	var base: int = int(species.base_stats.get(name, 1))
	var iv: int = int(ivs.get(name, 0))
	var ev: int = int(evs.get(name, 0))

	var inner: int = (2 * base + iv + (ev / 4)) * level / 100
	if stat_key == Enums.StatKey.HP:
		return inner + level + 10

	var raw: int = inner + 5
	return int(floor(raw * _nature_mod(stat_key)))

func max_hp() -> int:
	return stat(Enums.StatKey.HP)

## Nature multiplier for a given stat: 1.1, 1.0, or 0.9.
func _nature_mod(stat_key: int) -> float:
	if stat_key == Enums.StatKey.HP:
		return 1.0
	var effect := Enums.nature_effect(nature)
	var plus_stat: int = effect[0]
	var minus_stat: int = effect[1]
	if plus_stat == stat_key and minus_stat != stat_key:
		return 1.1
	if minus_stat == stat_key and plus_stat != stat_key:
		return 0.9
	return 1.0

## True if knocked out.
func is_fainted() -> bool:
	return current_hp <= 0

## Subtracts damage (clamped at 0). Returns the actual amount of HP lost.
func take_damage(amount: int) -> int:
	var before: int = current_hp
	current_hp = max(0, current_hp - amount)
	return before - current_hp

## Primary type (always index 0). Convenience.
func primary_type() -> int:
	return int(species.types[0]) if species.types.size() > 0 else Enums.Type.NONE

## All of the Pokémon's types (1 or 2 entries).
func type_list() -> Array:
	return species.types
