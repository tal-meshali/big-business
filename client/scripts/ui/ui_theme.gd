class_name UiTheme
## Builds the shared Godot Theme in code: the deed look from the design
## canvas. Archivo Black for display text and numbers, Nunito Sans for
## everything else, ink borders, hard offset shadows (HardBox) and a yellow
## primary button. Sizes are the design's CSS px times SCALE (390 -> 720).

## Design px (390-wide artboard) to project px (720-wide design size).
const SCALE := 720.0 / 390.0

static var _cached: Theme = null
static var _display: Font = null
static var _display_heavy: Font = null
static var _body: Font = null
static var _bold: Font = null


## Archivo ExtraBold: titles, counts, scores.
static func display() -> Font:
	if _display == null:
		_display = _load_font("res://assets/fonts/Archivo-ExtraBold.ttf")
	return _display


## Archivo Black: the heaviest display weight (brand plates, big buttons).
static func display_heavy() -> Font:
	if _display_heavy == null:
		_display_heavy = _load_font("res://assets/fonts/Archivo-Black.ttf")
	return _display_heavy


## Nunito Sans Bold: body copy.
static func body() -> Font:
	if _body == null:
		_body = _load_font("res://assets/fonts/NunitoSans-Bold.ttf")
	return _body


## Nunito Sans ExtraBold: labels, buttons, names.
static func bold() -> Font:
	if _bold == null:
		_bold = _load_font("res://assets/fonts/NunitoSans-ExtraBold.ttf")
	return _bold


static func _load_font(path: String) -> Font:
	var f = load(path)
	if f is Font:
		return f
	# WHY: a missing import (fresh checkout without --import) must not take
	# the whole UI down; the fallback font keeps every screen usable.
	return ThemeDB.fallback_font


## Round a design px value to project px.
static func px(design_px: float) -> float:
	return roundf(design_px * SCALE)


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = int(px(14))

	# Buttons: white face, ink border, hard shadow; pressed sinks 2 px.
	_button_styles(t, "Button", Companies.PANEL, Color("#FFF8E6"))
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Companies.PRIMARY, Companies.PRIMARY_HOVER)
	t.set_type_variation("GhostButton", "Button")
	_button_styles(t, "GhostButton", Companies.CARD_FACE, Color("#FFF8E6"))
	t.set_type_variation("BigButton", "Button")
	_button_styles(t, "BigButton", Companies.PRIMARY, Companies.PRIMARY_HOVER, px(14), px(5))
	t.set_font("font", "BigButton", display_heavy())
	t.set_font_size("font_size", "BigButton", int(px(20)))
	t.set_type_variation("DarkButton", "Button")
	_button_styles(t, "DarkButton", Companies.INK, Color("#333333"), px(10), px(3), Companies.CARD_FACE)

	# Inputs: cream box, ink border, orange focus ring.
	var edit := _flat(Companies.CARD_FACE, Companies.INK, px(2), px(10))
	edit.set_content_margin_all(px(10))
	t.set_stylebox("normal", "LineEdit", edit)
	var focus := _flat(Companies.CARD_FACE, Companies.CHANCE, px(3), px(10))
	focus.set_content_margin_all(px(10))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", Companies.INK)
	t.set_color("font_placeholder_color", "LineEdit", Color("#6A6A6A"))
	t.set_color("caret_color", "LineEdit", Companies.INK)
	t.set_font("font", "LineEdit", bold())
	t.set_font_size("font_size", "LineEdit", int(px(16)))

	t.set_color("font_color", "Label", Companies.INK)
	t.set_font_size("font_size", "Label", int(px(14)))
	t.set_font("font", "CheckButton", bold())
	t.set_color("font_color", "CheckButton", Companies.INK)
	t.set_color("font_hover_color", "CheckButton", Companies.INK)
	t.set_color("font_pressed_color", "CheckButton", Companies.INK)
	t.set_color("font_hover_pressed_color", "CheckButton", Companies.INK)
	t.set_font_size("font_size", "CheckButton", int(px(13)))

	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_bg)
	# Popup menus (seat menu) in the deed look.
	t.set_stylebox("panel", "PopupMenu", _flat(Companies.PANEL, Companies.INK, px(2), px(8)))
	t.set_color("font_color", "PopupMenu", Companies.INK)
	t.set_font("font", "PopupMenu", bold())
	t.set_font_size("font_size", "PopupMenu", int(px(14)))
	_cached = t
	return t


static func _button_styles(t: Theme, type: String, face: Color, hover: Color, radius: float = px(10), shadow: float = px(3), text: Color = Companies.INK) -> void:
	var normal := HardBox.new(face, radius, shadow)
	var hovered := HardBox.new(hover, radius, shadow)
	var pressed := HardBox.new(face, radius, shadow, px(2), shadow - px(1))
	var disabled := HardBox.new(face.lerp(Color("#DDDDDD"), 0.35), radius, shadow)
	disabled.border = Color("#7A7A7A")
	for s in [normal, hovered, pressed, disabled]:
		s.border_width = px(2)
		s.set_content_margin_all(px(6))
		s.content_margin_left = px(12)
		s.content_margin_right = px(12)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hovered)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("focus", type, normal)
	t.set_stylebox("disabled", type, disabled)
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, text)
	t.set_color("font_pressed_color", type, text)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_hover_pressed_color", type, text)
	t.set_color("font_disabled_color", type, Color("#7A7A7A"))
	t.set_font("font", type, bold())
	t.set_font_size("font_size", type, int(px(14)))


static func _flat(bg: Color, border: Color, width: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(width))
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	return s


## Public flat box for panels and pips.
static func flat(bg: Color, border: Color = Companies.INK, width: float = px(2), radius: float = px(10)) -> StyleBoxFlat:
	return _flat(bg, border, width, radius)


## A label with one of the theme fonts. `kind` is "display", "heavy",
## "body" or "bold"; `size_px` is in design px.
static func label(text: String, size_px: float, kind: String = "body", color: Color = Companies.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_of(kind))
	l.add_theme_font_size_override("font_size", int(px(size_px)))
	l.add_theme_color_override("font_color", color)
	return l


static func font_of(kind: String) -> Font:
	match kind:
		"display": return display()
		"heavy": return display_heavy()
		"bold": return bold()
		_: return body()


## A button in one of the theme variations ("", "PrimaryButton",
## "GhostButton", "BigButton", "DarkButton"); design px height.
static func button(text: String, variation: String = "", height_px: float = 44.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, px(height_px))
	return b


## A white panel with an ink border, a hard shadow and a coloured title
## band, used by the coach, the lobby cards and the dividend panel. Returns
## {"panel", "title", "band", "body"}; callers add content into `body`.
static func deed_panel(band_color: Color, title: String, band_text: Color = Color.WHITE) -> Dictionary:
	var panel := PanelContainer.new()
	var style := HardBox.new(Companies.PANEL, px(12), px(4))
	style.border_width = px(2)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	panel.clip_contents = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = band_color
	band_style.corner_radius_top_left = int(px(10))
	band_style.corner_radius_top_right = int(px(10))
	band_style.set_content_margin_all(px(12))
	band_style.content_margin_left = px(16)
	band_style.content_margin_right = px(16)
	band_style.border_color = Companies.INK
	band_style.border_width_bottom = int(px(2))
	band_style.anti_aliasing = true
	band.add_theme_stylebox_override("panel", band_style)
	column.add_child(band)
	var title_label := label(title, 18, "display", band_text)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title_label)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", int(px(14)))
	body.add_theme_constant_override("margin_right", int(px(14)))
	body.add_theme_constant_override("margin_top", int(px(12)))
	body.add_theme_constant_override("margin_bottom", int(px(14)))
	column.add_child(body)
	return {"panel": panel, "title": title_label, "band": band, "body": body}


## The dark room behind a table: a radial gradient from a lighter green at
## the table's centre to near-black at the edges, tinted by the felt.
static func room_background(felt: Color) -> TextureRect:
	var grad := Gradient.new()
	var mid := felt.darkened(0.55)
	mid.s = clampf(mid.s * 0.8, 0.0, 1.0)
	grad.set_color(0, mid.lightened(0.18))
	grad.set_color(1, mid.darkened(0.5))
	grad.add_point(0.62, mid)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.15, 0.42)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
