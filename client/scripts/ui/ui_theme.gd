class_name UiTheme
## Builds the shared Godot Theme in code: ink-on-white buttons and inputs
## with square-ish corners, so every screen matches the deed-card look.

const EMOJI_FONT_PATH := "res://fonts/emoji_subset.ttf"
## The only bitmap strike in Noto Color Emoji.
const EMOJI_STRIKE_PX := 109

static var _cached: Theme = null


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font = ui_font()

	var normal := _box(Companies.PANEL, Companies.INK, 2)
	var hover := _box(Companies.HIGHLIGHT, Companies.INK, 2)
	var pressed := _box(Companies.GOLD, Companies.INK, 2)
	var disabled := _box(Color("#EDEDED"), Color("#9A9A9A"), 2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", normal)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Companies.INK)
	t.set_color("font_hover_color", "Button", Companies.INK)
	t.set_color("font_pressed_color", "Button", Companies.INK)
	t.set_color("font_focus_color", "Button", Companies.INK)
	t.set_color("font_disabled_color", "Button", Color("#9A9A9A"))
	t.set_font_size("font_size", "Button", 22)

	var edit := _box(Companies.CARD_FACE, Companies.INK, 2)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(Companies.CARD_FACE, Companies.GOLD, 3))
	t.set_color("font_color", "LineEdit", Companies.INK)
	t.set_color("font_placeholder_color", "LineEdit", Companies.INK_SOFT)
	t.set_color("caret_color", "LineEdit", Companies.INK)
	t.set_font_size("font_size", "LineEdit", 22)

	t.set_color("font_color", "Label", Companies.INK)
	t.set_font_size("font_size", "Label", 19)

	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_bg)
	_cached = t
	return t


## The built-in UI font with the bundled emoji subset as a fallback.
## WHY: phones differ in which system emoji font Godot can reach, and a
## colour bitmap font only scales to the label size when told to, so the
## emotes and medals ship with the app instead of relying on the OS.
static func ui_font() -> Font:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	var emoji: FontFile = load(EMOJI_FONT_PATH)
	if emoji != null:
		emoji.fixed_size = EMOJI_STRIKE_PX
		emoji.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		font.fallbacks = [emoji]
	return font


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	return s


## A white panel with an ink border and a coloured title band, used by the
## coach and the dividend panel. Returns the PanelContainer; `band` receives
## the header row so callers can add the title label into it.
static func deed_panel(band_color: Color, title: String, band_text: Color = Color.WHITE) -> Dictionary:
	var panel := PanelContainer.new()
	var style := _box(Companies.PANEL, Companies.INK, 2)
	style.set_content_margin_all(0)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = band_color
	band_style.corner_radius_top_left = 8
	band_style.corner_radius_top_right = 8
	band_style.set_content_margin_all(14)
	band_style.border_color = Companies.INK
	band_style.border_width_bottom = 2
	band.add_theme_stylebox_override("panel", band_style)
	column.add_child(band)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", band_text)
	band.add_child(title_label)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 22)
	body.add_theme_constant_override("margin_right", 22)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 18)
	column.add_child(body)
	return {"panel": panel, "title": title_label, "body": body}
