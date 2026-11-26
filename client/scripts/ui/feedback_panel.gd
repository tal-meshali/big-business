class_name FeedbackPanel
extends VBoxContainer
## More > Send feedback: the body of a lobby sheet where a player tells the
## team about a bug, an idea or anything else (FeedbackApi). A strip picks
## the kind, one field takes the words, and a switch adds device details,
## shown word for word under it, so the player knows what goes with the
## message. Sent, the form gives way to a thank-you. A draft that was not
## sent stays for the next time the sheet opens.

## The sheet should close (Close, or Done after sending).
signal closed

## Design points to px; set before adding to the tree.
var s := 1.85

## Tab labels, the field's prompt for each, in FeedbackApi.CATEGORIES order.
const KINDS := [
	{"label": "Bug", "icon": "", "prompt": "What happened? What were you doing just before?"},
	{"label": "Idea", "icon": "", "prompt": "What would make the game better?"},
	{"label": "Other", "icon": "", "prompt": "What would you like to tell us?"},
]
## The counter shows from here on, so it only speaks when it matters.
const COUNT_FROM := 800
## WHY not Companies.ALERT: that red is for the light deed panels; on the
## night panel it is too dark to read, so problems use a soft coral.
const PROBLEM := Color("#FF9AA6")

var _form: VBoxContainer
var _thanks: VBoxContainer
var _kinds: TabStrip
var _edit: TextEdit
var _count: Label
var _details_switch: CheckButton
var _details_line: Label
var _note: Label
var _send: Button
var _actions: HBoxContainer
var _busy := false
## True once the player flips the switch: from then on their choice
## stands, whatever kind they pick.
var _details_chosen := false


func _px(dp: float) -> int:
	return int(round(dp * s))


func _ready() -> void:
	add_theme_constant_override("separation", _px(12))
	_build_form()
	_build_thanks()
	_pick_kind(0)


func _build_form() -> void:
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", _px(10))
	add_child(_form)
	var intro := UiTheme.body("A bug, an idea, anything. The team reads every message.", _px(UiTheme.TYPE_BODY))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(intro)

	_kinds = TabStrip.new()
	_kinds.setup(KINDS, s)
	_kinds.tab_selected.connect(_pick_kind)
	_form.add_child(_kinds)

	_edit = TextEdit.new()
	_edit.custom_minimum_size = Vector2(0, _px(108))
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.add_theme_font_size_override("font_size", _px(UiTheme.TYPE_BODY))
	_edit.add_theme_font_override("font", UiTheme.body_font())
	_edit.text_changed.connect(_on_text_changed)
	_form.add_child(_edit)

	# One line under the field: the privacy reminder, then the count near the limit.
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", _px(8))
	_form.add_child(under)
	# WHY body, not caption: captions are spaced capitals for section names,
	# too hard to read as a sentence.
	var privacy := UiTheme.body("Please leave out your email, phone number or address.", _px(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under.add_child(privacy)
	_count = UiTheme.body("", _px(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
	_count.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	under.add_child(_count)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", _px(2))
	_form.add_child(details)
	_details_switch = CheckButton.new()
	_details_switch.text = "Add device details"
	_details_switch.custom_minimum_size = Vector2(0, _px(44))
	_details_switch.add_theme_font_size_override("font_size", _px(UiTheme.TYPE_LABEL))
	_details_switch.toggled.connect(func(_on: bool) -> void:
		_details_chosen = true
		_show_details())
	details.add_child(_details_switch)
	_details_line = UiTheme.body(FeedbackApi.describe(FeedbackApi.device_details()), _px(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
	_details_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_details_line)

	_note = UiTheme.body("", _px(UiTheme.TYPE_LABEL), PROBLEM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	_form.add_child(_note)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", _px(10))
	_form.add_child(_actions)
	var close := UiTheme.button("Close", _px(14), _px(48), "ghost")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: closed.emit())
	_actions.add_child(close)
	_send = UiTheme.button("Send", _px(14), _px(48), "primary")
	_send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send.pressed.connect(_on_send)
	_actions.add_child(_send)
	# The lobby keeps the buttons above the on-screen keyboard with the field.
	_edit.set_meta(NamePrompt.KEEP_IN_VIEW, _actions)
	_refresh_send()


func _build_thanks() -> void:
	_thanks = VBoxContainer.new()
	_thanks.add_theme_constant_override("separation", _px(10))
	_thanks.visible = false
	add_child(_thanks)
	_thanks.add_child(UiTheme.title("Thank you!", _px(UiTheme.TYPE_TITLE), UiTheme.GOLD))
	var line := UiTheme.body("Your message reached the team. We can't answer in the app, but every message helps.", _px(UiTheme.TYPE_BODY))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_thanks.add_child(line)
	var done := UiTheme.button("Done", _px(14), _px(48), "primary")
	done.pressed.connect(func() -> void: closed.emit())
	_thanks.add_child(done)


## Back to the form (after a thank-you), keeping any unsent draft.
func reset_view() -> void:
	_thanks.visible = false
	_form.visible = true
	_note.visible = false


func category() -> String:
	return FeedbackApi.CATEGORIES[_kinds.current]


func _pick_kind(i: int) -> void:
	_kinds.select(i, is_inside_tree())
	_edit.placeholder_text = KINDS[i]["prompt"]
	# Details help with a bug; for an idea they are noise. The player's own
	# choice wins once they have made one.
	if not _details_chosen:
		_details_switch.set_pressed_no_signal(FeedbackApi.CATEGORIES[i] == "bug")
	_show_details()


func _show_details() -> void:
	_details_line.modulate.a = 1.0 if _details_switch.button_pressed else 0.45


func _on_text_changed() -> void:
	if _edit.text.length() > FeedbackApi.MAX_LENGTH:
		var line := _edit.get_caret_line()
		var column := _edit.get_caret_column()
		_edit.text = _edit.text.left(FeedbackApi.MAX_LENGTH)
		_edit.set_caret_line(mini(line, _edit.get_line_count() - 1))
		_edit.set_caret_column(column)
	var n := _edit.text.length()
	_count.text = "%d / %d" % [n, FeedbackApi.MAX_LENGTH] if n >= COUNT_FROM else ""
	_note.visible = false
	_refresh_send()


func _refresh_send() -> void:
	_send.disabled = _busy or not FeedbackApi.problem(_edit.text).is_empty()


func _on_send() -> void:
	if _busy:
		return
	_busy = true
	_send.text = "Sending…"
	_refresh_send()
	var problem: String = await FeedbackApi.send(category(), _edit.text, _details_switch.button_pressed)
	_busy = false
	_send.text = "Send"
	_refresh_send()
	if not problem.is_empty():
		_note.text = problem
		_note.visible = true
		return
	_edit.text = ""
	_count.text = ""
	_details_chosen = false
	_pick_kind(0)
	_refresh_send()
	_form.visible = false
	_thanks.visible = true
