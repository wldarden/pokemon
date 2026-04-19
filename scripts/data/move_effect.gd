class_name MoveEffect
extends Resource
## Describes a secondary effect of a move (status, stat change, recoil, ...).
## Phase 1 only reads `kind` and `chance`; the rest is reserved.

enum Kind {
	NONE           = 0,
	INFLICT_STATUS = 1,   # e.g. Ember's 10% burn
	STAT_CHANGE    = 2,   # Phase 2+
	RECOIL         = 3,   # Phase 2+
	HEAL           = 4,   # Phase 2+
}

@export var kind: int = Kind.NONE
@export var chance: int = 0                    # 0-100 percent
@export var status: int = 0                    # Enums.StatusCondition (if kind==INFLICT_STATUS)
@export var stat_change_target: String = ""    # "self" | "target" (Phase 2+)
@export var stat_change_stat: int = 0          # Enums.StatKey (Phase 2+)
@export var stat_change_stages: int = 0        # -6..+6 (Phase 2+)
