class_name Direction
extends RefCounted
## Shared 4-way direction enum + vector/name helpers.

enum {
	DOWN  = 0,
	UP    = 1,
	LEFT  = 2,
	RIGHT = 3,
}

const VECTORS := {
	DOWN:  Vector2i(0, 1),
	UP:    Vector2i(0, -1),
	LEFT:  Vector2i(-1, 0),
	RIGHT: Vector2i(1, 0),
}

const NAMES := {
	DOWN:  "down",
	UP:    "up",
	LEFT:  "left",
	RIGHT: "right",
}

static func vec(dir: int) -> Vector2i:
	return VECTORS.get(dir, Vector2i.ZERO)

static func name_of(dir: int) -> String:
	return NAMES.get(dir, "down")
