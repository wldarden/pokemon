extends CanvasLayer
## Battle scene. Owns the turn loop, state machine, and UI feedback.
## Rendered on its own CanvasLayer so it overlays the Overworld regardless of
## camera position when instantiated mid-scene.
##
## Public API:
##   start(player_party, enemy_party, context) — begin the battle.
##   signal battle_ended(result: BattleResult)
##
## Phase 1.2 scope: 1v1, no switching, no items, no catching, no running.
## Status effects and PP depletion are deferred to Phase 2.

signal battle_ended(result: BattleResult)

@onready var enemy_sprite: Sprite2D = $EnemySprite
@onready var player_sprite: Sprite2D = $PlayerSprite
@onready var enemy_hp_fill: ColorRect = $EnemyHUD/HPFill
@onready var enemy_hp_bg: Panel = $EnemyHUD/HPBarBG
@onready var enemy_name_label: Label = $EnemyHUD/NameLabel
@onready var player_hp_fill: ColorRect = $PlayerHUD/HPFill
@onready var player_hp_bg: Panel = $PlayerHUD/HPBarBG
@onready var player_name_label: Label = $PlayerHUD/NameLabel
@onready var player_hp_label: Label = $PlayerHUD/HPNumbers
@onready var dialog_box: Panel = $DialogBox
@onready var dialog_label: Label = $DialogBox/DialogLabel
@onready var move_menu: Panel = $MoveMenu
@onready var move_buttons: Array[Panel] = [
	$MoveMenu/Move1, $MoveMenu/Move2, $MoveMenu/Move3, $MoveMenu/Move4,
]
@onready var move_labels: Array[Label] = [
	$MoveMenu/Move1/Label, $MoveMenu/Move2/Label,
	$MoveMenu/Move3/Label, $MoveMenu/Move4/Label,
]
@onready var cursor: Panel = $MoveMenu/Cursor

# Phase 2c: PartyScreen is instantiated on demand when POKéMON is picked
# or the active mon faints. Uses a preload for the script so we can type
# the var and reference Mode by name despite the cross-file class_name
# resolution limitation in headless parse.
const PARTY_SCREEN := preload("res://scenes/ui/PartyScreen.tscn")
const PartyScreenScript := preload("res://scripts/ui/party_screen.gd")
var _party_screen: PartyScreenScript = null

@onready var action_menu: Panel = $ActionMenu
@onready var action_buttons: Array[Panel] = [
	$ActionMenu/Fight, $ActionMenu/Pokemon,
	$ActionMenu/Bag, $ActionMenu/Run,
]

const ACTION_FIGHT := 0
const ACTION_POKEMON := 1
const ACTION_BAG := 2
const ACTION_RUN := 3

var selected_action_idx: int = 0

var player_party: Array = []
var enemy_party: Array = []
var context: BattleContext

# Which slot of each side is currently on the field. Active index drives
# `player_mon` / `enemy_mon` rebinding on every switch.
var player_active_idx: int = 0
var enemy_active_idx: int = 0

# Indices into `player_party` that have been active during the current
# enemy mon's lifetime — the set of eligible XP-split recipients. Reset
# whenever the enemy changes.
var current_opponent_participants: Array[int] = []

var player_mon: PokemonInstance
var enemy_mon: PokemonInstance

enum State {
	BOOTING,
	ACTION_MENU,     # top-level FIGHT / POKéMON / BAG / RUN picker
	MOVE_MENU,       # existing 2x2 move grid (was CHOOSE_ACTION)
	PARTY_MENU,      # PartyScreen open (wired in 2c.7)
	SWITCHING_IN,    # "Come back / Go" narration (wired in 2c.7)
	FAINT_SWITCH,    # forced-switch PartyScreen after active KO (wired in 2c.8)
	RESOLVING,
	ENDED,
}
var state: int = State.BOOTING
var selected_move_idx: int = 0

const HP_BAR_WIDTH := 48.0
const HP_TWEEN_DURATION := 0.6
const DIALOG_LINGER := 0.8       # time dialog stays after typing finishes
const CHAR_PRINT_DELAY := 0.03   # seconds per character in the typewriter effect

func _ready() -> void:
	dialog_box.visible = false
	move_menu.visible = false
	action_menu.visible = false
	enemy_hp_bg.visible = false
	player_hp_bg.visible = false

## Call this right after instantiating the scene to configure and begin.
func start(p_player: Array, p_enemy: Array, p_context: BattleContext) -> void:
	player_party = p_player
	enemy_party = p_enemy
	context = p_context
	player_active_idx = PartyHelpers.first_non_fainted(player_party)
	enemy_active_idx = PartyHelpers.first_non_fainted(enemy_party)
	if player_active_idx < 0 or enemy_active_idx < 0:
		push_error("Battle.start: a side has no usable Pokémon.")
		return
	player_mon = player_party[player_active_idx]
	enemy_mon = enemy_party[enemy_active_idx]
	current_opponent_participants = [player_active_idx]

	_apply_sprites()
	_refresh_hp_bars(true)
	_refresh_labels()
	_refresh_move_menu()

	enemy_hp_bg.visible = true
	player_hp_bg.visible = true
	dialog_box.visible = true

	_enter_action_menu()

func _process(_delta: float) -> void:
	match state:
		State.ACTION_MENU:
			_handle_action_menu_input()
		State.MOVE_MENU:
			_handle_menu_input()

# ---- Display / refresh -----------------------------------------------------

func _apply_sprites() -> void:
	if enemy_mon.species.front_sprite:
		enemy_sprite.texture = enemy_mon.species.front_sprite
	if player_mon.species.back_sprite:
		player_sprite.texture = player_mon.species.back_sprite

func _refresh_labels() -> void:
	enemy_name_label.text = "%s L%d" % [enemy_mon.species.species_name, enemy_mon.level]
	player_name_label.text = "%s L%d" % [player_mon.species.species_name, player_mon.level]
	player_hp_label.text = "%d/%d" % [player_mon.current_hp, player_mon.max_hp()]

func _refresh_hp_bars(instant: bool) -> void:
	_set_hp_fill(enemy_hp_fill, enemy_mon, instant)
	_set_hp_fill(player_hp_fill, player_mon, instant)

func _set_hp_fill(fill: ColorRect, mon: PokemonInstance, instant: bool) -> void:
	var pct: float = 0.0
	if mon.max_hp() > 0:
		pct = float(mon.current_hp) / float(mon.max_hp())
	var target_w: float = HP_BAR_WIDTH * pct
	if instant:
		fill.size.x = target_w
		fill.color = _hp_color(pct)
	else:
		var tw := create_tween()
		tw.tween_property(fill, "size:x", target_w, HP_TWEEN_DURATION)
		tw.parallel().tween_property(fill, "color", _hp_color(pct), HP_TWEEN_DURATION)

func _hp_color(pct: float) -> Color:
	if pct > 0.5:  return Color(0.35, 0.82, 0.30)
	if pct > 0.2:  return Color(0.98, 0.80, 0.20)
	return Color(0.95, 0.25, 0.25)

func _refresh_move_menu() -> void:
	for i in 4:
		var btn: Panel = move_buttons[i]
		var lbl: Label = move_labels[i]
		if i < player_mon.moves.size():
			btn.visible = true
			lbl.text = player_mon.moves[i].move.move_name
		else:
			btn.visible = false
			lbl.text = ""
	_clamp_cursor()
	_update_cursor_position()

func _set_dialog(msg: String) -> void:
	dialog_label.text = msg

## Waits until ui_accept is pressed. Used to gate level-up screens.
func _await_confirm() -> void:
	# Ensure the player has released any in-flight ui_accept (the one that
	# dismissed the previous screen) before we start listening. Otherwise a
	# held Enter key would skip through both screens in one frame.
	while Input.is_action_pressed("ui_accept"):
		await get_tree().process_frame
	while not Input.is_action_just_pressed("ui_accept"):
		await get_tree().process_frame

## Temporarily expands the DialogBox (and its inner Label) to span the full
## bottom bar of the viewport with enough vertical room for the 3-line stat
## layout, shows the two level-up screens for one LevelUpEvent (each gated
## on ui_accept), then restores the original sizes.
func _show_level_up_screens(event: LevelUpEvent) -> void:
	var box_pos: Vector2 = dialog_box.position
	var box_size: Vector2 = dialog_box.size
	var label_size: Vector2 = dialog_label.size

	# Grow up-and-right: top moves up by 16px, width expands to 232, total
	# height 56 (fits header + blank + 3 stat lines at ~10 px/line).
	dialog_box.position = Vector2(box_pos.x, 100.0)
	dialog_box.size = Vector2(232.0, 56.0)
	# The Label is a child of DialogBox; its position stays relative, only
	# size needs to grow.
	dialog_label.size = Vector2(220.0, 48.0)

	await _print_dialog("%s grew to Lv. %d!" % [player_mon.species.species_name, event.new_level])
	_set_dialog(_format_delta_screen(event))
	await _await_confirm()

	_set_dialog(_format_totals_screen(event))
	await _await_confirm()

	dialog_box.position = box_pos
	dialog_box.size = box_size
	dialog_label.size = label_size
	_set_dialog("")

# ---- Move learning (Phase 2b) --------------------------------------------

## Drive the FR/LG-style learn flow for one new move. Auto-learn if a slot is
## free; otherwise narrate, prompt Y/N, then (on YES) show the move-to-forget
## menu. Cancelling the move selection loops back to the Y/N prompt so the
## player can change their mind.
func _try_learn_move(mon: PokemonInstance, move: Move) -> void:
	if mon.moves.size() < 4:
		mon.moves.append(MoveSlot.from_move(move))
		_refresh_move_menu()
		await _print_dialog("%s learned %s!" % [mon.species.species_name, move.move_name])
		return

	await _print_dialog("%s is trying to learn %s..." % [mon.species.species_name, move.move_name])
	await _print_dialog("But %s already knows 4 moves." % mon.species.species_name)

	while true:
		var replace: bool = await _yes_no_prompt(
			"Forget a move to make room for %s?" % move.move_name
		)
		if not replace:
			await _print_dialog("%s did not learn %s." % [mon.species.species_name, move.move_name])
			return
		var idx: int = await _select_move_to_forget(mon)
		if idx == -1:
			# Cancelled — give the player another chance to answer the prompt.
			continue
		var forgotten: Move = mon.moves[idx].move
		mon.moves[idx] = MoveSlot.from_move(move)
		_refresh_move_menu()
		await _print_dialog("Forgot %s and learned %s!" % [forgotten.move_name, move.move_name])
		return

## Prints `question`, then shows the move menu repurposed as a YES/NO picker.
## Returns true for YES, false for NO or cancel.
func _yes_no_prompt(question: String) -> bool:
	await _print_dialog(question)

	# Relabel the top two move buttons as YES/NO. Hide the bottom two.
	move_labels[0].text = "YES"
	move_labels[1].text = "NO"
	move_buttons[0].visible = true
	move_buttons[1].visible = true
	move_buttons[2].visible = false
	move_buttons[3].visible = false
	selected_move_idx = 0
	_update_cursor_position_for_yes_no()
	move_menu.visible = true

	# Let the ui_accept that dismissed the dialog fully release first.
	while Input.is_action_pressed("ui_accept"):
		await get_tree().process_frame

	var result: bool = true
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_left"):
			selected_move_idx = 1 - selected_move_idx   # toggle 0↔1
			_update_cursor_position_for_yes_no()
		elif Input.is_action_just_pressed("ui_accept"):
			result = (selected_move_idx == 0)
			break
		elif Input.is_action_just_pressed("ui_cancel"):
			result = false
			break

	move_menu.visible = false
	cursor.visible = false
	_refresh_move_menu()   # restore real move labels + button visibility
	return result

## Show the move menu as a "pick a move to forget" selector.
## Returns the index (0..3) of the chosen move, or -1 if the player cancelled.
func _select_move_to_forget(mon: PokemonInstance) -> int:
	await _print_dialog("Which move should be forgotten?")

	_refresh_move_menu()   # real labels, all 4 buttons visible
	selected_move_idx = 0
	_update_cursor_position()
	move_menu.visible = true

	while Input.is_action_pressed("ui_accept"):
		await get_tree().process_frame

	var result_idx: int = -1
	while true:
		await get_tree().process_frame
		var move_count: int = mon.moves.size()
		if Input.is_action_just_pressed("ui_right"):
			selected_move_idx = (selected_move_idx + 1) % move_count
			_update_cursor_position()
		elif Input.is_action_just_pressed("ui_left"):
			selected_move_idx = (selected_move_idx - 1 + move_count) % move_count
			_update_cursor_position()
		elif Input.is_action_just_pressed("ui_down") and selected_move_idx + 2 < move_count:
			selected_move_idx += 2
			_update_cursor_position()
		elif Input.is_action_just_pressed("ui_up") and selected_move_idx - 2 >= 0:
			selected_move_idx -= 2
			_update_cursor_position()
		elif Input.is_action_just_pressed("ui_accept"):
			result_idx = selected_move_idx
			break
		elif Input.is_action_just_pressed("ui_cancel"):
			result_idx = -1
			break

	move_menu.visible = false
	cursor.visible = false
	return result_idx

## YES/NO layout doesn't use the main `_update_cursor_position` because that
## one clamps to `player_mon.moves.size()` — which might be 4, putting the
## cursor on a hidden button. Always wrap the top-left or top-right button.
func _update_cursor_position_for_yes_no() -> void:
	cursor.visible = true
	var btn: Panel = move_buttons[selected_move_idx]
	cursor.position = btn.position + Vector2(-2, -2)
	cursor.size = btn.size + Vector2(4, 4)

func _format_delta_screen(event: LevelUpEvent) -> String:
	# Three-per-row layout (physical on top, special/speed on bottom) — fits
	# in ~3 content lines (header + 2 stat rows) well within the expanded
	# dialog box.
	var d: Dictionary = event.stat_deltas
	return "%s grew to Lv. %d!\n\n  HP %+d   ATK %+d   DEF %+d\n  SPA %+d  SPD %+d   SPE %+d" % [
		player_mon.species.species_name, event.new_level,
		int(d["hp"]),  int(d["atk"]), int(d["def"]),
		int(d["spa"]), int(d["spd"]), int(d["spe"]),
	]

func _format_totals_screen(event: LevelUpEvent) -> String:
	# Shows old=>new so the player can eyeball progression at a glance,
	# without having to remember the deltas from screen 1.
	var o: Dictionary = event.old_stats
	var n: Dictionary = event.new_stats
	return "%s  L%d\n\n  HP: %d=>%d  ATK: %d=>%d  DEF: %d=>%d\n  SPA: %d=>%d  SPD: %d=>%d  SPE: %d=>%d" % [
		player_mon.species.species_name, event.new_level,
		int(o["hp"]),  int(n["hp"]),
		int(o["atk"]), int(n["atk"]),
		int(o["def"]), int(n["def"]),
		int(o["spa"]), int(n["spa"]),
		int(o["spd"]), int(n["spd"]),
		int(o["spe"]), int(n["spe"]),
	]

## Typewriter: reveals the message one character at a time, then lingers.
## Ui_accept (Enter/Space) skips the typing animation. The final linger is
## always applied so players have time to read.
func _print_dialog(msg: String) -> void:
	dialog_label.text = msg
	dialog_label.visible_ratio = 0.0
	var total_chars := msg.length()
	if total_chars == 0:
		return
	var tw := create_tween()
	tw.tween_property(dialog_label, "visible_ratio", 1.0, CHAR_PRINT_DELAY * total_chars)
	while tw.is_running():
		if Input.is_action_just_pressed("ui_accept"):
			tw.kill()
			dialog_label.visible_ratio = 1.0
			break
		await get_tree().process_frame
	await get_tree().create_timer(DIALOG_LINGER).timeout

# ---- ACTION_MENU / MOVE_MENU states ---------------------------------------

func _enter_action_menu() -> void:
	state = State.ACTION_MENU
	_refresh_labels()
	_set_dialog("What will %s do?" % player_mon.species.species_name)
	action_menu.visible = true
	move_menu.visible = false
	selected_action_idx = 0
	_update_action_cursor()

func _enter_move_menu() -> void:
	state = State.MOVE_MENU
	action_menu.visible = false
	move_menu.visible = true
	_clamp_cursor()
	_update_cursor_position()

func _handle_menu_input() -> void:
	var move_count: int = player_mon.moves.size()
	if move_count == 0:
		return
	var changed := false
	if Input.is_action_just_pressed("ui_right"):
		selected_move_idx = (selected_move_idx + 1) % move_count
		changed = true
	elif Input.is_action_just_pressed("ui_left"):
		selected_move_idx = (selected_move_idx - 1 + move_count) % move_count
		changed = true
	elif Input.is_action_just_pressed("ui_down"):
		# Move down by two positions in the 2x2 grid.
		if selected_move_idx + 2 < move_count:
			selected_move_idx += 2
			changed = true
	elif Input.is_action_just_pressed("ui_up"):
		if selected_move_idx - 2 >= 0:
			selected_move_idx -= 2
			changed = true
	elif Input.is_action_just_pressed("ui_accept"):
		_submit_player_move(selected_move_idx)
		return

	if changed:
		_update_cursor_position()

func _clamp_cursor() -> void:
	var n: int = player_mon.moves.size()
	if n == 0:
		selected_move_idx = 0
	elif selected_move_idx >= n:
		selected_move_idx = n - 1

func _update_cursor_position() -> void:
	if selected_move_idx >= player_mon.moves.size():
		cursor.visible = false
		return
	cursor.visible = true
	var btn: Panel = move_buttons[selected_move_idx]
	# Wrap the cursor around the selected button as a 1px outline.
	cursor.position = btn.position + Vector2(-2, -2)
	cursor.size = btn.size + Vector2(4, 4)

func _handle_action_menu_input() -> void:
	var changed := false
	if Input.is_action_just_pressed("ui_right") and selected_action_idx % 2 == 0:
		selected_action_idx += 1
		changed = true
	elif Input.is_action_just_pressed("ui_left") and selected_action_idx % 2 == 1:
		selected_action_idx -= 1
		changed = true
	elif Input.is_action_just_pressed("ui_down") and selected_action_idx < 2:
		selected_action_idx += 2
		changed = true
	elif Input.is_action_just_pressed("ui_up") and selected_action_idx >= 2:
		selected_action_idx -= 2
		changed = true
	elif Input.is_action_just_pressed("ui_accept"):
		_submit_action(selected_action_idx)
		return

	if changed:
		_update_action_cursor()

func _update_action_cursor() -> void:
	cursor.visible = true
	var btn: Panel = action_buttons[selected_action_idx]
	# Cursor is a child of MoveMenu but we're pointing it at an ActionMenu
	# button. Works because ActionMenu shares MoveMenu's top-left (140,112),
	# so button.position is valid in both parent spaces. If either menu moves,
	# this needs a reparent or coordinate translation.
	cursor.position = btn.position + Vector2(-2, -2)
	cursor.size = btn.size + Vector2(4, 4)

func _submit_action(idx: int) -> void:
	match idx:
		ACTION_FIGHT:
			_enter_move_menu()
		ACTION_POKEMON:
			_open_party_screen_switch()
		ACTION_BAG:
			await _print_dialog("The BAG is empty…")
			_enter_action_menu()
		ACTION_RUN:
			_try_run()

func _try_run() -> void:
	if context.is_trainer:
		await _print_dialog("No! There's no running from a trainer battle!")
		_enter_action_menu()
		return
	await _print_dialog("Got away safely!")
	state = State.ENDED
	var result := BattleResult.new()
	result.outcome = BattleResult.Outcome.ESCAPED
	battle_ended.emit(result)

# ---- PARTY_MENU / SWITCHING_IN states --------------------------------------

func _open_party_screen_switch() -> void:
	state = State.PARTY_MENU
	action_menu.visible = false
	_party_screen = PARTY_SCREEN.instantiate()
	add_child(_party_screen)
	_party_screen.slot_chosen.connect(_on_party_slot_chosen_voluntary)
	_party_screen.cancelled.connect(_on_party_cancelled_voluntary)
	_party_screen.open(player_party, player_active_idx, PartyScreenScript.Mode.SWITCH_IN_BATTLE)

func _on_party_slot_chosen_voluntary(idx: int) -> void:
	_close_party_screen()
	await _switch_to(idx, false)
	# Switch spent the turn — enemy attacks. Single-mon enemy party is
	# assumed in 2c.7; multi-mon trainer flow lands in 2c.8.
	var enemy_move: Move = _choose_enemy_move()
	await _resolve_enemy_only_turn(enemy_move)

func _on_party_cancelled_voluntary() -> void:
	_close_party_screen()
	_enter_action_menu()

func _close_party_screen() -> void:
	if _party_screen != null:
		_party_screen.queue_free()
		_party_screen = null

func _switch_to(idx: int, is_forced: bool) -> void:
	state = State.SWITCHING_IN
	if not is_forced:
		await _print_dialog("Come back, %s!" % player_mon.species.species_name)
	player_active_idx = idx
	player_mon = player_party[idx]
	if not current_opponent_participants.has(idx):
		current_opponent_participants.append(idx)
	_apply_sprites()
	_refresh_hp_bars(true)
	_refresh_labels()
	_refresh_move_menu()
	await _print_dialog("Go, %s!" % player_mon.species.species_name)

# ---- RESOLVING state -------------------------------------------------------

func _submit_player_move(idx: int) -> void:
	state = State.RESOLVING
	move_menu.visible = false
	cursor.visible = false

	var player_move: Move = player_mon.moves[idx].move
	var enemy_move: Move = _choose_enemy_move()

	_resolve_turn(player_move, enemy_move)

## Decide which side acts first based on priority then Speed.
func _turn_order(p_move: Move, e_move: Move) -> Array:
	if p_move.priority != e_move.priority:
		return [player_mon, p_move, enemy_mon, e_move] \
			if p_move.priority > e_move.priority \
			else [enemy_mon, e_move, player_mon, p_move]
	var p_spe: int = player_mon.stat(Enums.StatKey.SPEED)
	var e_spe: int = enemy_mon.stat(Enums.StatKey.SPEED)
	if p_spe == e_spe:
		# Random tie-break.
		return [player_mon, p_move, enemy_mon, e_move] \
			if context.rng.randi_range(0, 1) == 0 \
			else [enemy_mon, e_move, player_mon, p_move]
	return [player_mon, p_move, enemy_mon, e_move] \
		if p_spe > e_spe \
		else [enemy_mon, e_move, player_mon, p_move]

func _resolve_turn(p_move: Move, e_move: Move) -> void:
	var order := _turn_order(p_move, e_move)
	var first_attacker: PokemonInstance = order[0]
	var first_move: Move = order[1]
	var second_attacker: PokemonInstance = order[2]
	var second_move: Move = order[3]

	await _execute_attack(first_attacker, second_attacker, first_move)
	if second_attacker.is_fainted():
		await _handle_faint(second_attacker)
		return
	await _execute_attack(second_attacker, first_attacker, second_move)
	if first_attacker.is_fainted():
		await _handle_faint(first_attacker)
		return
	_enter_action_menu()

## After a voluntary switch-in the enemy attacks uncontested. Same turn
## order rules apply minus the player's attack half.
func _resolve_enemy_only_turn(e_move: Move) -> void:
	state = State.RESOLVING
	await _execute_attack(enemy_mon, player_mon, e_move)
	if player_mon.is_fainted():
		await _handle_faint(player_mon)
		return
	_enter_action_menu()

func _execute_attack(attacker: PokemonInstance, defender: PokemonInstance, move: Move) -> void:
	await _print_dialog("%s used %s!" % [attacker.species.species_name, move.move_name])

	var result: DamageCalc.Result = DamageCalc.calculate(attacker, defender, move, context)
	if result.missed:
		await _print_dialog("%s's attack missed!" % attacker.species.species_name)
		return

	if result.damage > 0:
		defender.take_damage(result.damage)
		_refresh_hp_bars(false)
		_refresh_labels()
		await get_tree().create_timer(HP_TWEEN_DURATION).timeout

	# Post-damage narration.
	if result.crit:
		await _print_dialog("A critical hit!")
	if result.effectiveness == 0.0:
		await _print_dialog("It doesn't affect %s..." % defender.species.species_name)
	elif result.effectiveness > 1.0 and result.damage > 0:
		await _print_dialog("It's super effective!")
	elif result.effectiveness < 1.0 and result.effectiveness > 0.0 and result.damage > 0:
		await _print_dialog("It's not very effective...")

func _choose_enemy_move() -> Move:
	# Dumb random policy — fine for Phase 1.2.
	if enemy_mon.moves.is_empty():
		# Struggle fallback would go here. Phase 1: just reuse player's first move as a stand-in.
		return player_mon.moves[0].move
	var idx: int = context.rng.randi_range(0, enemy_mon.moves.size() - 1)
	return enemy_mon.moves[idx].move

# ---- XP distribution / bench level-ups -------------------------------------

## Returns {participant_idx: xp_share} for the current enemy's KO.
## Defensive fallback: if the participant set is empty (shouldn't happen —
## the active mon is always added to the set on switch-in), default to just
## the currently-active index so nobody is skipped.
func _compute_participant_xp_split(total: int) -> Dictionary:
	var participants: Array = current_opponent_participants.duplicate()
	if participants.is_empty():
		participants = [player_active_idx]
	var out := {}
	var each: int = XpFormula.split_among_participants(total, participants.size())
	for idx in participants:
		out[idx] = each
	return out

## Silently apply each LevelUpEvent for a benched participant:
##   - Stats already updated by gain_exp (it calls _level_up per threshold).
##   - For each event, auto-learn any new moves if a slot is free.
##   - Skip (no replace prompt) when the mon already knows 4 moves.
func _apply_bench_levelups(mon: PokemonInstance, events: Array[LevelUpEvent]) -> void:
	for event in events:
		var new_moves: Array[Move] = LearnsetResolver.moves_learned_at(
			mon.species, event.new_level
		)
		for move in new_moves:
			if LearnsetResolver.already_knows(mon, move):
				continue
			if mon.moves.size() < 4:
				mon.moves.append(MoveSlot.from_move(move))
			# else: silent skip — no replace prompt for benched mons.

# ---- Faint / outcome -------------------------------------------------------

func _handle_faint(mon: PokemonInstance) -> void:
	await _print_dialog("%s fainted!" % mon.species.species_name)

	var result := BattleResult.new()
	if mon == enemy_mon:
		result.outcome = BattleResult.Outcome.WIN
		var total_xp: int = _compute_xp_for_opponent(enemy_mon)
		result.xp_gained = total_xp
		var splits: Dictionary = _compute_participant_xp_split(total_xp)

		# Narrate each participant's gain in party-slot order (FR/LG
		# convention) rather than dict-insertion order (switch-in order).
		# Invisible today with ≤2 participants but will matter in 2c.8
		# when multi-mon enemy teams allow 3+ switch-ins.
		var sorted_ids := splits.keys()
		sorted_ids.sort()
		# Active mon gets full level-up screens + learn-move flow; benched
		# participants apply their level-ups silently (auto-learn, no prompt).
		for idx in sorted_ids:
			var amount: int = splits[idx]
			var p_mon: PokemonInstance = player_party[idx]
			await _print_dialog("%s gained %d EXP!" % [p_mon.species.species_name, amount])
			var events: Array[LevelUpEvent] = p_mon.gain_exp(amount)
			if events.is_empty():
				continue
			if p_mon == player_mon:
				# Reflect new max HP in the HUD before showing stat screens.
				_refresh_hp_bars(false)
				_refresh_labels()
				for event in events:
					await _show_level_up_screens(event)
					var new_moves: Array[Move] = LearnsetResolver.moves_learned_at(
						p_mon.species, event.new_level
					)
					for move in new_moves:
						if LearnsetResolver.already_knows(p_mon, move):
							continue
						await _try_learn_move(p_mon, move)
			else:
				_apply_bench_levelups(p_mon, events)

		# 2c.7 still assumes a single-mon enemy party, so any enemy faint
		# ends the battle. Multi-mon trainer progression lands in 2c.8.
		state = State.ENDED
	else:
		state = State.ENDED
		result.outcome = BattleResult.Outcome.LOSE
		await _print_dialog("You are out of usable Pokémon!")

	battle_ended.emit(result)

## Thin wrapper around XpFormula — applies the context's is_trainer flag.
func _compute_xp_for_opponent(mon: PokemonInstance) -> int:
	return XpFormula.exp_for_kill(mon, context.is_trainer)
