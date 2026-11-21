class_name NamePrompt
extends ColorRect
## The name step: a sheet with one field, under the player's investor card,
## which fills in as they type. Shown once at first launch, when the account
## still has the random name the server made (`required`: no way out but a
## name), and from the profile's "Change name" (with Cancel).
## The lobby lifts it above the on-screen keyboard like its other sheets.

signal saved(player_name: String)
signal cancelled

const CARD_DP := 150.0
## Metadata on a text field: the control under it that the lobby keeps
## above the on-screen keyboard together with the field.
const KEEP_IN_VIEW := &"keep_in_view"

## Design points to px, and the phone's bottom inset in px.
var s := 1.85
var bottom_inset := 0.0
var required := true
var _card: InvestorCard
var _sheet: PanelContainer
var _title: Label
var _hint: Label
var _edit: LineEdit
var _error: Label
var _save: Button
var _cancel: Button
var _column: VBoxContainer
var _busy := false
var _tween: Tween


func _ready() -> void:
	color = Color(UiTheme.NIGHT, 0.86)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_column = VBoxContainer.new()
	_column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.offset_left = _px(16)
	_column.offset_right = -_px(16)
	_column.offset_bottom = -_px(16) - bottom_inset
	_column.add_theme_constant_override("separation", _px(14))
	add_child(_column)

	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(holder)
	_card = InvestorCard.new()
	_card.custom_minimum_size = InvestorCard.size_for(Vector2(_px(CARD_DP), _px(CARD_DP)))
	_card.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	holder.add_child(_card)

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
	_edit.placeholder_text = "Your name"
	_edit.max_length = NamesApi.MAX_LENGTH
	_edit.custom_minimum_size = Vector2(0, _px(48))
	_edit.add_theme_font_override("font", UiTheme.display_font())
	_edit.add_theme_font_size_override("font_size", _px(18))
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_edit.text_changed.connect(_on_typed)
	_edit.text_submitted.connect(func(_t: String) -> void: _on_save())
	body.add_child(_edit)

	# WHY a fixed line: the sheet must not jump when an error appears.
	_error = UiTheme.label("", _px(13), Companies.ALERT)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(0, _px(16))
	body.add_child(_error)

	_save = UiTheme.button("", _px(16), _px(52), "primary")
	_save.pressed.connect(_on_save)
	body.add_child(_save)
	# WHY: the error line and Save sit under the field, where the keyboard
	# would cover them.
	_edit.set_meta(KEEP_IN_VIEW, _save)
	_cancel = UiTheme.button("Cancel", _px(14), _px(44), "ghost")
	_cancel.pressed.connect(_on_cancel)
	body.add_child(_cancel)


func _px(dp: float) -> int:
	return int(round(dp * s))


## Shows the step with `current` in the field. `must_name` hides Cancel:
## the player has no name yet and cannot play without one.
func open(current: String, must_name: bool, level := 1) -> void:
	required = must_name
	_busy = false
	_title.text = "What's your name?" if required else "Change your name"
	_hint.text = "Other players see it at the table. You can change it later in your profile." if required else "Other players see it at the table, and friends add you by it."
	_save.text = "Let's play" if required else "Save name"
	_cancel.text = "Cancel"
	_cancel.visible = not required
	_error.text = ""
	_edit.text = current
	_edit.editable = true
	_card.level = level
	_card.show_face()
	_on_typed(current)
	visible = true
	_edit.grab_focus()
	_edit.select_all()
	_play_open()


## The sheet rises and the card settles on top of it.
func _play_open() -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2(0.9, 0.9)
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_card.play_sheen)


func _on_typed(typed: String) -> void:
	_card.player_name = NamesApi.clean(typed)
	_error.text = ""
	_save.disabled = _busy or not NamesApi.problem(typed).is_empty()


func _on_save() -> void:
	if _busy or _save.disabled:
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
	_save.text = "Let's play" if required else "Save name"
	if not problem.is_empty():
		_show_error(problem)
		return
	_edit.release_focus()
	visible = false
	saved.emit(wanted)


## Says what went wrong under the field and nudges the field sideways.
func _show_error(message: String) -> void:
	_error.text = message
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
	if _busy:
		return
	_edit.release_focus()
	visible = false
	cancelled.emit()
