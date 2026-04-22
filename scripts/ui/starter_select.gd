class_name StarterSelect
extends CanvasLayer
## Phase 2d — first-boot modal. Three Poké Ball slots; arrow-nav; A confirm.
## No cancel. Emits `starter_chosen(dex_number: int)` on pick.

signal starter_chosen(dex_number: int)

const DEX_NUMBERS: Array[int] = [1, 4, 7]  # Bulbasaur, Charmander, Squirtle

@onready var slots: Array[Panel] = [
	$Root/Slots/Slot1, $Root/Slots/Slot2, $Root/Slots/Slot3,
]

var _selected: int = 0

func _ready() -> void:
	_update_cursor()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % 3
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + 3) % 3
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		starter_chosen.emit(DEX_NUMBERS[_selected])
		get_viewport().set_input_as_handled()

func _update_cursor() -> void:
	for i in slots.size():
		slots[i].self_modulate = Color(1, 1, 0.125, 1) if i == _selected else Color(1, 1, 1, 1)
