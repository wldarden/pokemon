class_name Move
extends Resource
## Immutable template for a move. One .tres file per move.

@export var move_name: String = ""
@export var type: int = 0             # Enums.Type
@export var category: int = 0         # Enums.Category
@export var power: int = 0            # 0 for status moves
@export var accuracy: int = 100       # 0 for moves that never miss
@export var pp: int = 10
@export var priority: int = 0

# Optional secondary effect. Null in Phase 1 for plain damage moves.
@export var effect: MoveEffect
