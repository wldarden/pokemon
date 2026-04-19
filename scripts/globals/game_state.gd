extends Node
## Persistent game state, autoloaded as /root/GameState.
## Survives scene transitions (overworld -> battle -> overworld).
## Expanded in later phases; Phase 1.1 only uses player_position / player_facing.

# Player party — populated in Phase 1.2 when battle lands.
# Typed as Array; element type (PokemonInstance) enforced once that class exists.
var player_party: Array = []

# Where the player stood on the overworld when a battle started.
# Restored after the battle ends.
var player_position: Vector2i = Vector2i.ZERO
var player_facing: int = 0  # Direction enum — defined in scripts/overworld/direction.gd later.

# Trainer IDs that have already been defeated (keys are trainer_id strings).
var defeated_trainers: Dictionary = {}

# Pokedex flags.
var pokedex_seen: Dictionary = {}
var pokedex_caught: Dictionary = {}
