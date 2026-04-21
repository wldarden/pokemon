class_name PartyScreen
extends CanvasLayer
## Phase 2c: reusable party screen for Battle and Overworld.
##
## Modes:
##   SWITCH_IN_BATTLE  — caller wants the player to pick a switch-in; cancel OK.
##   FORCED_SWITCH     — after active faint; cancel disabled; fainted slots un-selectable.
##   OVERWORLD_REORDER — pick two slots to swap; stays open for more swaps; B closes.
##
## The scene is single-instance: caller preloads the .tscn, instantiates,
## add_child's, connects signals, calls open(), and frees the node when done.
## Submenu + Summary views are added in task 2c.6.

enum Mode { SWITCH_IN_BATTLE, FORCED_SWITCH, OVERWORLD_REORDER }

signal slot_chosen(idx: int)
signal swap_requested(a: int, b: int)
signal cancelled

const SLOT_COUNT := 6
const SWAP_TWEEN_DURATION := 0.25

@onready var lead_slot: Panel = $Root/LeadSlot
@onready var slot_panels: Array[Panel] = [
	$Root/Stack/Slot1, $Root/Stack/Slot2, $Root/Stack/Slot3,
	$Root/Stack/Slot4, $Root/Stack/Slot5,
]
@onready var hint_label: Label = $Root/Hint
@onready var cursor: Panel = $Root/Cursor

var _mode: int = Mode.OVERWORLD_REORDER
var _party: Array = []
var _active_idx: int = 0
var _selected: int = 0                 # 0 == lead, 1..5 == stack
var _swap_first_pick: int = -1         # for OVERWORLD_REORDER

func _ready() -> void:
	visible = false

func open(p_party: Array, p_active_idx: int, p_mode: int) -> void:
	_party = p_party
	_active_idx = p_active_idx
	_mode = p_mode
	_selected = 0
	_swap_first_pick = -1
	_refresh_all_slots()
	_update_hint()
	_update_cursor()
	visible = true

func close() -> void:
	visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
	elif event.is_action_pressed("ui_accept"):
		_on_confirm()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel()

func _move_cursor(delta: int) -> void:
	var next: int = _selected + delta
	if next < 0 or next >= _party.size():
		return
	_selected = next
	_update_cursor()

func _on_confirm() -> void:
	if _mode == Mode.OVERWORLD_REORDER:
		if _swap_first_pick == -1:
			_swap_first_pick = _selected
			_update_hint()
		elif _swap_first_pick == _selected:
			_swap_first_pick = -1
			_update_hint()
		else:
			var a := _swap_first_pick
			var b := _selected
			_swap_first_pick = -1
			swap_requested.emit(a, b)
			await _animate_swap(a, b)
			_update_hint()
	else:
		if not _can_select_slot(_selected):
			return
		slot_chosen.emit(_selected)

func _on_cancel() -> void:
	if _mode == Mode.FORCED_SWITCH:
		return
	if _mode == Mode.OVERWORLD_REORDER and _swap_first_pick != -1:
		_swap_first_pick = -1
		_update_hint()
		return
	cancelled.emit()

func _can_select_slot(idx: int) -> bool:
	if idx < 0 or idx >= _party.size():
		return false
	var mon = _party[idx]
	if mon == null:
		return false
	if _mode == Mode.SWITCH_IN_BATTLE or _mode == Mode.FORCED_SWITCH:
		return PartyHelpers.can_switch_to(_party, idx, _active_idx)
	return true

func _refresh_all_slots() -> void:
	_refresh_slot(lead_slot, 0)
	for i in slot_panels.size():
		_refresh_slot(slot_panels[i], i + 1)

func _refresh_slot(panel: Panel, idx: int) -> void:
	if idx >= _party.size() or _party[idx] == null:
		panel.modulate = Color(0.5, 0.5, 0.5, 0.6)
		_set_slot_text(panel, "(empty)", "", 0, 0)
		return
	var mon: PokemonInstance = _party[idx]
	var label := "%s :L%d" % [mon.species.species_name, mon.level]
	var hp_text := "HP: %d/%d" % [mon.current_hp, mon.max_hp()]
	panel.modulate = Color(1, 1, 1, 0.6) if mon.is_fainted() else Color.WHITE
	_set_slot_text(panel, label, hp_text, mon.current_hp, mon.max_hp())

func _set_slot_text(panel: Panel, name_text: String, hp_text: String, hp_cur: int, hp_max: int) -> void:
	(panel.get_node("NameLabel") as Label).text = name_text
	(panel.get_node("HPLabel") as Label).text = hp_text
	var fill: ColorRect = panel.get_node("HPFill")
	var pct: float = 0.0 if hp_max == 0 else float(hp_cur) / float(hp_max)
	var parent_size: Vector2 = (fill.get_parent() as Control).size
	fill.size.x = parent_size.x * pct

func _update_hint() -> void:
	match _mode:
		Mode.SWITCH_IN_BATTLE:
			hint_label.text = "Choose a POKéMON.   B: back"
		Mode.FORCED_SWITCH:
			hint_label.text = "Send out which POKéMON?"
		Mode.OVERWORLD_REORDER:
			if _swap_first_pick == -1:
				hint_label.text = "Pick first slot.   B: close"
			else:
				hint_label.text = "Pick partner (A on same slot to cancel)."

func _update_cursor() -> void:
	var target: Panel = lead_slot if _selected == 0 else slot_panels[_selected - 1]
	cursor.position = target.position + (target.get_parent() as Control).position
	cursor.size = target.size
	cursor.visible = true

func _animate_swap(a: int, b: int) -> void:
	# After the caller swapped the underlying _party array, redraw slots.
	# Cosmetic: briefly tween the two panels' scale to give a visible "swap".
	var panel_a := _panel_for_idx(a)
	var panel_b := _panel_for_idx(b)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel_a, "scale", Vector2(0.9, 0.9), SWAP_TWEEN_DURATION / 2.0)
	tw.tween_property(panel_b, "scale", Vector2(0.9, 0.9), SWAP_TWEEN_DURATION / 2.0)
	await tw.finished
	_refresh_all_slots()
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(panel_a, "scale", Vector2(1, 1), SWAP_TWEEN_DURATION / 2.0)
	tw2.tween_property(panel_b, "scale", Vector2(1, 1), SWAP_TWEEN_DURATION / 2.0)
	await tw2.finished
	_update_cursor()

func _panel_for_idx(idx: int) -> Panel:
	return lead_slot if idx == 0 else slot_panels[idx - 1]
