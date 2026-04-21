class_name LevelUpEvent
extends RefCounted
## Payload returned by PokemonInstance._level_up() and accumulated in an
## Array by gain_exp(). The battle scene consumes these events to drive the
## two level-up screens.

var old_level: int = 0
var new_level: int = 0

# {hp, atk, def, spa, spd, spe} snapshots — same keys as Species.base_stats.
var old_stats: Dictionary = {}
var new_stats: Dictionary = {}

# Per-stat deltas (new - old). Always ≥ 0 for HP; others can theoretically
# shift slightly due to nature rounding but usually increase.
var stat_deltas: Dictionary = {}

# Specifically the HP delta, also stored in stat_deltas["hp"]. Kept as its
# own field so the UI doesn't have to reach into the dict just for HP.
var hp_delta: int = 0
