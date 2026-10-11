class_name AgeScreen
extends Control
## The neutral age screen (decision D4), shown over the lobby the first time
## an account connects without an age answer. Three age ranges, no default
## and no "are you over 13?" gate; only the range is stored, on the server.
## The answer sets what the player may do later (uploading card art, seeing
## custom decks in quick play), never whether they may play.

signal answered(bracket: String)

## [button text, bracket] in the order shown; the brackets are the server's
## AGE_BRACKETS (server/src/match/designer.ts).
const ANSWERS := [["Under 13", "under13"], ["13 to 15", "13to15"], ["16 or older", "16plus"]]

## Sends an answer and returns the server's reply ({} on failure). Tests
## replace it; the default is DesignerApi.set_age.
var send: Callable = func(bracket: String) -> Dictionary: return await DesignerApi.set_age(bracket)

var _buttons: Array[Button] = []
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var deed := UiTheme.deed_panel(Companies.CHEST, "Welcome to Big Business", Color.WHITE)
	deed["panel"].custom_minimum_size = Vector2(600, 0)
	center.add_child(deed["panel"])

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	deed["body"].add_child(column)
	column.add_child(_label("How old are you?", 26))
	column.add_child(_label("This keeps the game right for your age. Only the age range is saved.", 20))
	for answer in ANSWERS:
		var bracket: String = answer[1]
		var b := Button.new()
		b.text = answer[0]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _on_answer(bracket))
		column.add_child(b)
		_buttons.append(b)
	_status = _label("", 18)
	column.add_child(_status)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Companies.INK)
	return l


func _on_answer(bracket: String) -> void:
	for b in _buttons:
		b.disabled = true
	_status.text = ""
	var res: Dictionary = await send.call(bracket)
	if res.is_empty():
		_status.text = DesignerApi.last_error if not DesignerApi.last_error.is_empty() else "Could not save that. Try again."
		for b in _buttons:
			b.disabled = false
		return
	answered.emit(String(res.get("ageBracket", bracket)))
	queue_free()


## Opens the age screen on top of `parent` and returns it.
static func open_over(parent: Control) -> AgeScreen:
	var screen := AgeScreen.new()
	parent.add_child(screen)
	return screen
