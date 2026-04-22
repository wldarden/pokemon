extends CanvasLayer
## Phase 2d autoload singleton. Reusable overworld dialog box with
## typewriter effect. Not used inside the Battle scene — battle has its
## own dialog with the same CHAR_PRINT_DELAY pacing.
##
## Public API:
##   queue(lines: Array[String]) -> Signal    # returns `closed` signal
##   is_open() -> bool

signal closed

const CHAR_PRINT_DELAY := 0.03
const DIALOG_LINGER := 0.3

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label

var _open: bool = false
var _advance_requested: bool = false

func _ready() -> void:
	panel.visible = false

## Display a sequence of dialog lines, one at a time, waiting for
## ui_accept between each. Returns the `closed` signal so callers can
## `await DialogBox.queue([...])`.
func queue(lines: Array[String]) -> Signal:
	# If already open, wait for the current sequence to finish first.
	if _open:
		await closed
	_run(lines)
	return closed

func is_open() -> bool:
	return _open

# ---- Internal -------------------------------------------------------------

func _run(lines: Array[String]) -> void:
	_open = true
	panel.visible = true
	_lock_player_input(true)
	for line in lines:
		await _print_line(line)
	panel.visible = false
	_lock_player_input(false)
	_open = false
	closed.emit()

func _print_line(line: String) -> void:
	label.text = line
	label.visible_ratio = 0.0
	var total_chars: int = line.length()
	if total_chars == 0:
		return
	var tw := create_tween()
	tw.tween_property(label, "visible_ratio", 1.0, CHAR_PRINT_DELAY * total_chars)
	# Typewriter can be skipped by pressing ui_accept.
	_advance_requested = false
	while tw.is_running():
		if _advance_requested:
			tw.kill()
			label.visible_ratio = 1.0
			break
		await get_tree().process_frame
	# After typewriter finishes, wait for another ui_accept to advance.
	_advance_requested = false
	while not _advance_requested:
		await get_tree().process_frame
	# Small linger so rapid A-presses don't skip the NEXT line.
	await get_tree().create_timer(DIALOG_LINGER).timeout

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_accept"):
		_advance_requested = true
		get_viewport().set_input_as_handled()

func _lock_player_input(locked: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if "input_locked" in p:
			p.input_locked = locked
