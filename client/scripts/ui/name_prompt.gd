class_name NamePrompt
extends ColorRect
## The name step: a sheet with one field, under the player's investor card,
## which fills in as they type. Shown once at first launch, when the account
## still has the random name the server made (`required`: no way out but a
## name), and from the profile's "Change name" (with Cancel, and a tap
## outside the sheet cancels too).
## The lobby lifts it above the on-screen keyboard like its other sheets.

signal saved(player_name: String)
signal cancelled

const CARD_MIN_DP := 110.0
const CARD_MAX_DP := 230.0
## Metadata on a text field: the control under it that the lobby keeps
## above the on-screen keyboard together with the field.
const KEEP_IN_VIEW := &"keep_in_view"

## Design points to px, and the phone's bottom inset in px.
var s := 1.85
var bottom_inset := 0.0
var required := true
var _card: InvestorCard
var _stage: Control
var _sheet: PanelContainer
var _title: Label
var _hint: Label
var _edit: LineEdit
var _note: Label
var _save: Button
var _cancel: Button
var _rise: Control
var _column: VBoxContainer
var _busy := false
var _open := false
var _tween: Tween


func _ready() -> void:
	# WHY this dark: the lobby's logo and dock must not read through as
	# stray letters round the card.
	color = Color(UiTheme.NIGHT, 0.93)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	gui_input.connect(_on_backdrop_input)

	_rise = Control.new()
	_rise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rise)
	_column = VBoxContainer.new()
	_column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.offset_left = _px(16)
	_column.offset_right = -_px(16)
	_column.offset_bottom = -_px(16) - bottom_inset
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", _px(10))
	_rise.add_child(_column)

	# WHY a plain Control: a container would undo the card's tilt.
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_place_card)
	_column.add_child(_stage)
	_card = InvestorCard.new()
	_card.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	_stage.add_child(_card)

	var deed := UiTheme.deed_panel(Companies.CHANCE, "", Color.WHITE)
	_sheet = deed["panel"]
	_title = deed["title"]
	_title.add_theme_font_size_override("font_size", _px(18))
	_column.add_child(_sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(10))
	deed["body"].add_child(body)

	_hint = UiTheme.label("", _px(14))
	_hint.add_theme_font_override("font", UiTheme.body_font())
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)

	_edit = LineEdit.new()
	_edit.placeholder_text = "Nickname"
	_edit.max_length = NamesApi.MAX_LENGTH
	_edit.custom_minimum_size = Vector2(0, _px(48))
	_edit.add_theme_font_override("font", UiTheme.display_font())
	_edit.add_theme_font_size_override("font_size", _px(18))
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_edit.text_changed.connect(_on_typed)
	_edit.text_submitted.connect(func(_t: String) -> void: _on_save())
	body.add_child(_edit)

	# One line under the field: what a name may be, or what is wrong with
	# this one. WHY always there: the sheet must not jump when it changes.
	_note = UiTheme.label(NamesApi.RULES, _px(13), Companies.INK_SOFT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(0, _px(16))
	body.add_child(_note)

	# Cancel and Save share a row, so both stay above the keyboard.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", _px(8))
	body.add_child(actions)
	_cancel = UiTheme.button("Cancel", _px(14), _px(52), "ghost")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(_on_cancel)
	actions.add_child(_cancel)
	_save = UiTheme.button("", _px(16), _px(52), "primary")
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save.size_flags_stretch_ratio = 1.6
	_save.pressed.connect(_on_save)
	actions.add_child(_save)
	# WHY: the note and the buttons sit under the field, where the keyboard
	# would cover them.
	_edit.set_meta(KEEP_IN_VIEW, actions)

	resized.connect(_fit)
	_sheet.minimum_size_changed.connect(_fit)


func _px(dp: float) -> int:
	return int(round(dp * s))


## True from `open` until the step is saved or cancelled.
func is_open() -> bool:
	return _open


## Shows the step with `current` in the field. `must_name` hides Cancel:
## the player has no name yet and cannot play without one.
func open(current: String, must_name: bool, level := 1) -> void:
	required = must_name
	_busy = false
	_open = true
	_title.text = "Pick a name" if required else "Change your name"
	_hint.text = "Other players see it at the table, so use a nickname, not your real name. You can change it later in your profile." if required \
			else "Other players see it at the table, and friends add you by it. Use a nickname, not your real name."
	_save.text = _save_text()
	_cancel.text = "Cancel"
	_cancel.visible = not required
	_edit.text = current
	_edit.editable = true
	_card.level = level
	_card.show_face()
	_on_typed(current)
	visible = true
	_fit()
	_edit.grab_focus()
	_edit.select_all()
	_play_open()


func _save_text() -> String:
	return "Let's play" if required else "Save name"


## The card takes the room the sheet leaves, within its smallest and
## largest size.
func _fit() -> void:
	if _stage == null or not visible:
		return
	var room := size.y - bottom_inset - _sheet.get_combined_minimum_size().y - _px(72)
	var stage_h := clampf(room, _px(CARD_MIN_DP), _px(CARD_MAX_DP))
	if absf(_stage.custom_minimum_size.y - stage_h) > 0.5:
		_stage.custom_minimum_size.y = stage_h
	_place_card()


func _place_card() -> void:
	if _card == null or _stage.size.y <= 0:
		return
	# Leave the tilt's corners and the drop shadow inside the stage.
	_card.size = InvestorCard.size_for(Vector2(_stage.size.x, _stage.size.y - _px(14)))
	_card.position = (_stage.size - _card.size) / 2.0 - Vector2(0, _px(3))
	_card.pivot_offset = _card.size / 2.0


## The sheet rises and the card settles on top of it.
func _play_open() -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	_rise.position.y = _px(24)
	_card.scale = Vector2(0.9, 0.9)
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_rise, "position:y", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_card.play_sheen)


## Out faster than in: the player has already moved on.
func _close() -> void:
	_open = false
	_edit.release_focus()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		# Reopened while fading out: stay.
		if not _open:
			visible = false)


func _on_typed(typed: String) -> void:
	_card.player_name = NamesApi.clean(typed)
	_say("")
	_save.disabled = _busy or not NamesApi.problem(typed).is_empty()


## Shows what is wrong under the field, or the rules when nothing is.
func _say(problem: String) -> void:
	_note.text = problem if not problem.is_empty() else NamesApi.RULES
	_note.add_theme_color_override("font_color", Companies.ALERT if not problem.is_empty() else Companies.INK_SOFT)


func _on_save() -> void:
	if _busy or _save.disabled or not _open:
		return
	var wanted := NamesApi.clean(_edit.text)
	# The same name again is nothing to save when changing it.
	if not required and wanted == Net.display_name:
		_on_cancel()
		return
	_busy = true
	_save.disabled = true
	_save.text = "Saving..."
	_edit.editable = false
	var problem: String = await NamesApi.save(wanted)
	_busy = false
	_edit.editable = true
	_save.text = _save_text()
	if not problem.is_empty():
		_show_error(problem)
		return
	_close()
	saved.emit(wanted)


## Says what went wrong under the field and nudges the field sideways.
func _show_error(message: String) -> void:
	_say(message)
	_save.disabled = not NamesApi.problem(_edit.text).is_empty()
	# WHY: a first launch must never trap the player behind an outage; the
	# lobby asks again on the next connection.
	if required and message in [NamesApi.OFFLINE, NamesApi.FAILED, NamesApi.BUSY]:
		_cancel.text = "Not now"
		_cancel.visible = true
	_edit.grab_focus()
	var x := _edit.position.x
	var shake := create_tween()
	for dx in [-6.0, 5.0, -3.0, 0.0]:
		shake.tween_property(_edit, "position:x", x + dx * s, 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_cancel() -> void:
	if _busy or not _open:
		return
	_close()
	cancelled.emit()


## A tap outside the sheet cancels, where Cancel is offered.
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _cancel.visible:
		_on_cancel()
