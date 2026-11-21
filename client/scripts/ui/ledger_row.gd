class_name LedgerRow
extends Button
## One line of the profile's record, set like the rent table on a title
## deed: a label, a dotted leader and the value in Archivo Black. A row with
## `leads_to` set is a button with a chevron (Season opens the standings,
## Club the clubs, Look the card-back picker); the others only inform.

## Design points to px.
var s := 1.85
var value: String:
	get:
		return _value.text
	set(v):
		_value.text = v
		_fit_value()
var label: String:
	get:
		return _label.text
	set(v):
		_label.text = v
		_fit_value()
var _label: Label
var _value: Label
var _leader: Control
var _chevron: Control
var _tappable := false


## `tappable` rows are a full touch target and show a chevron.
static func make(label: String, value: String, scale_px: float, tappable := false) -> LedgerRow:
	var row := LedgerRow.new()
	row.s = scale_px
	row._tappable = tappable
	row._build(label, value)
	return row


func _build(label: String, value: String) -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	custom_minimum_size = Vector2(0, (44.0 if _tappable else 28.0) * s)
	mouse_filter = Control.MOUSE_FILTER_STOP if _tappable else Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var down := StyleBoxFlat.new()
	down.bg_color = Companies.HIGHLIGHT
	down.set_corner_radius_all(int(8 * s))
	down.anti_aliasing = true
	add_theme_stylebox_override("pressed", down)
	add_theme_stylebox_override("hover_pressed", down)

	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6 * s
	box.offset_right = -6 * s
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(6 * s))
	add_child(box)

	_label = UiTheme.label(label, int(14 * s), Companies.INK)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_label)

	_leader = Control.new()
	_leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_leader.custom_minimum_size = Vector2(12 * s, 0)
	_leader.draw.connect(_draw_leader)
	box.add_child(_leader)

	_value = UiTheme.label(value, int(14 * s), Companies.INK, true)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A long club name or a huge count gives way before the label does.
	_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_value)

	_chevron = Control.new()
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.custom_minimum_size = Vector2(10 * s, 0)
	_chevron.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chevron.visible = _tappable
	_chevron.draw.connect(_draw_chevron)
	box.add_child(_chevron)
	resized.connect(_fit_value)
	_fit_value()


## The value may take what the label leaves, and is cut with an ellipsis
## past that, so the row never grows wider than its panel.
## WHY the explicit width: a Label that may trim reports no minimum width,
## and the leader beside it would squeeze it to nothing.
func _fit_value() -> void:
	if _value == null:
		return
	var font := UiTheme.display_font()
	var natural := font.get_string_size(_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s)).x + 2.0
	var taken := 12 * s + _label.get_combined_minimum_size().x + _leader.custom_minimum_size.x + 6 * s * 2
	if _tappable:
		taken += _chevron.custom_minimum_size.x + 6 * s
	var room := size.x - taken
	_value.custom_minimum_size.x = natural if size.x <= 0 or natural <= room else maxf(40 * s, room)


## Dots on the text baseline, from the label to the value.
func _draw_leader() -> void:
	var y := _leader.size.y / 2.0 + 4 * s
	var step := 5.0 * s
	var x := step / 2.0
	while x < _leader.size.x:
		_leader.draw_circle(Vector2(x, y), 0.9 * s, Color(Companies.INK_SOFT, 0.55), true, -1.0, true)
		x += step


func _draw_chevron() -> void:
	var c := _chevron.size / 2.0
	var k := 4.0 * s
	_chevron.draw_polyline(PackedVector2Array([c + Vector2(-k * 0.45, -k), c + Vector2(k * 0.55, 0), c + Vector2(-k * 0.45, k)]), Companies.INK, maxf(2.0, 2.2 * s), true)
