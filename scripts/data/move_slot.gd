class_name MoveSlot
extends RefCounted
## A move known by a PokémonInstance — tracks current PP.

var move: Move
var pp_current: int = 0

static func from_move(m: Move) -> MoveSlot:
	var slot := MoveSlot.new()
	slot.move = m
	slot.pp_current = m.pp
	return slot
