class_name UiTheme
## Builds the shared Godot Theme in code, after the "3D table" design:
## cream and white faces with ink borders, a hard ink drop under every
## button and panel, Archivo Black for headings and Nunito Sans for text.
##
## Screens laid out from the design (lobby, table, coach) size everything in
## design points (dp) of the 390 x 844 phone artboard, times `layout_scale`.

const EMOJI_FONT_PATH := "res://fonts/emoji_subset.ttf"
const DISPLAY_FONT_PATH := "res://fonts/archivo_black.ttf"
const TEXT_FONT_PATH := "res://fonts/nunito_sans_extrabold.ttf"
const BODY_FONT_PATH := "res://fonts/nunito_sans_bold.ttf"
## The only bitmap strike in Noto Color Emoji.
const EMOJI_STRIKE_PX := 109

## Size of the design artboard, in dp.
const DESIGN_W := 390.0
const DESIGN_H := 844.0

## Button faces.
const PRIMARY := Color("#F2C230")
const PRIMARY_HOVER := Color("#F6CF52")
const HOVER := Color("#FFF8E6")
## Orange ring on whatever you can tap right now.
const RING := Color("#F7941D")
const CREAM := Color("#FFFDF6")
const MUTED := Color("#4A4A4A")
const XP_GREEN := Color("#3F9E4F")
const PLATE_ON := Color("#FFF1C9")

static var _cached: Theme = null
static var _fonts: Dictionary = {}


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font = ui_font()

	_button_styles(t, "Button", Companies.PANEL, HOVER, 10, 3)
	t.set_color("font_color", "Button", Companies.INK)
	t.set_color("font_hover_color", "Button", Companies.INK)
	t.set_color("font_pressed_color", "Button", Companies.INK)
	t.set_color("font_focus_color", "Button", Companies.INK)
	t.set_color("font_hover_pressed_color", "Button", Companies.INK)
	t.set_color("font_disabled_color", "Button", Color(Companies.INK, 0.45))
	t.set_font_size("font_size", "Button", 22)
	# Yellow call to action, cream secondary, and the tall "Play now".
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", PRIMARY, PRIMARY_HOVER, 10, 3)
	t.set_type_variation("GhostButton", "Button")
	_button_styles(t, "GhostButton", CREAM, HOVER, 10, 3)
	t.set_type_variation("BigButton", "Button")
	_button_styles(t, "BigButton", PRIMARY, PRIMARY_HOVER, 14, 5)
	t.set_font("font", "BigButton", display_font())

	var edit := _box(CREAM, Companies.INK, 2)
	edit.set_corner_radius_all(10)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := _box(CREAM, RING, 3)
	edit_focus.set_corner_radius_all(10)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", Companies.INK)
	t.set_color("font_placeholder_color", "LineEdit", Color("#6A6A6A"))
	t.set_color("caret_color", "LineEdit", Companies.INK)
	t.set_font_size("font_size", "LineEdit", 22)

	t.set_color("font_color", "Label", Companies.INK)
	t.set_font_size("font_size", "Label", 19)

	var track := _box(Color("#EEF0EA"), Companies.INK, 2)
	track.set_corner_radius_all(8)
	track.set_content_margin_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = XP_GREEN
	fill.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)

	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_bg)
	_cached = t
	return t


## Design points to pixels for a viewport: the 390 dp artboard fills the
## width, unless the screen is too short for its 844 dp height.
## Space the phone's notch or Dynamic Island (top) and home indicator
## (bottom) take from the screen, in canvas units; zero off phones.
## WHY: desktop safe areas are relative to the monitor, not the window.
static func safe_insets(ci: CanvasItem) -> Vector2:
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var win := ci.get_window()
	var safe := DisplayServer.get_display_safe_area()
	if win == null or win.size.y <= 0 or safe.size.y <= 0:
		return Vector2.ZERO
	var k := ci.get_viewport_rect().size.y / float(win.size.y)
	var top := maxf(0.0, float(safe.position.y - win.position.y)) * k
	var bottom := maxf(0.0, float(win.position.y + win.size.y - safe.end.y)) * k
	return Vector2(top, bottom)


static func layout_scale(viewport: Vector2) -> float:
	if viewport.x < 200 or viewport.y < 200:
		viewport = Vector2(720, 1280)
	return clampf(minf(viewport.x / DESIGN_W, viewport.y / DESIGN_H), 1.2, 2.6)


## The text font (Nunito Sans ExtraBold) with the bundled emoji subset and
## the engine font as fallbacks.
## WHY: phones differ in which system emoji font Godot can reach, and a
## colour bitmap font only scales to the label size when told to, so the
## emotes ship with the app instead of relying on the OS.
static func ui_font() -> Font:
	return _font_with_fallbacks("ui", TEXT_FONT_PATH)


## Lighter weight for paragraphs: prompts and coach text.
static func body_font() -> Font:
	return _font_with_fallbacks("body", BODY_FONT_PATH)


## Archivo Black: titles, card counts, scores.
static func display_font() -> Font:
	return _font_with_fallbacks("display", DISPLAY_FONT_PATH)


static func _font_with_fallbacks(key: String, path: String) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var font := FontVariation.new()
	var base: FontFile = load(path)
	font.base_font = base if base != null else ThemeDB.fallback_font
	var fallbacks: Array[Font] = []
	var emoji: FontFile = load(EMOJI_FONT_PATH)
	if emoji != null:
		emoji.fixed_size = EMOJI_STRIKE_PX
		emoji.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		fallbacks.append(emoji)
	# Names in other scripts fall back to the engine font.
	fallbacks.append(ThemeDB.fallback_font)
	font.fallbacks = fallbacks
	_fonts[key] = font
	return font


## Button faces: an ink border with a thicker bottom edge standing in for the
## design's hard drop shadow; pressed, the drop shrinks and the label sinks.
static func _button_styles(t: Theme, type: String, bg: Color, hover_bg: Color, radius: int, drop: int) -> void:
	var normal := _button_box(bg, radius, drop, false)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, _button_box(hover_bg, radius, drop, false))
	t.set_stylebox("pressed", type, _button_box(hover_bg, radius, drop, true))
	t.set_stylebox("hover_pressed", type, _button_box(hover_bg, radius, drop, true))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	var off := _button_box(bg, radius, drop, false)
	off.bg_color = bg.lerp(Color("#E4E4E0"), 0.55)
	off.border_color = Color(Companies.INK, 0.4)
	t.set_stylebox("disabled", type, off)


static func _button_box(bg: Color, radius: int, drop: int, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Companies.INK
	s.set_border_width_all(2)
	s.border_width_bottom = 2 + (1 if pressed else drop)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6 + (drop - 1 if pressed else 0)
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	return s


## A panel face: ink border, rounded, with a hard ink drop of `drop` px.
static func card_box(bg: Color, radius: float, drop: float, border: float = 2.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Companies.INK
	s.set_border_width_all(int(round(border)))
	s.border_width_bottom = int(round(border + drop))
	s.set_corner_radius_all(int(round(radius)))
	s.set_content_margin_all(0)
	s.anti_aliasing = true
	return s


## The dark room around the felt, derived from the picked felt so every
## table skin gets a matching room: [centre, middle, edge] of the glow.
static func room_colors(felt: Color) -> Array[Color]:
	var sat := clampf(felt.s * 3.5, 0.18, 0.6)
	return [
		Color.from_hsv(felt.h, sat, 0.42),
		Color.from_hsv(felt.h, sat, 0.23),
		Color.from_hsv(felt.h, sat, 0.13),
	]


## A full-screen radial glow (centre at `center`, in 0..1 of the rect).
static func room_background(felt: Color, center: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	paint_room(rect, felt, center)
	return rect


static func paint_room(rect: TextureRect, felt: Color, center: Vector2) -> void:
	var c := room_colors(felt)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([c[0], c[1], c[2]])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = center + Vector2(0.0, 0.72)
	tex.width = 128
	tex.height = 256
	rect.texture = tex


## A label in one of the bundled fonts at a pixel size.
static func label(text: String, px: int, color: Color = Companies.INK, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	if display:
		l.add_theme_font_override("font", display_font())
	return l


## A solid ink "play" triangle, `px` tall, for the Play now button.
static func play_icon(px: int) -> ImageTexture:
	var n := maxi(8, px)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		# Edges meet at the right-hand tip; one pixel of fade smooths them.
		var half := (1.0 - absf((y + 0.5) - n / 2.0) / (n / 2.0)) * n * 0.86
		for x in n:
			var a := clampf(half - (x + 0.5) + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(Companies.INK, a))
	return ImageTexture.create_from_image(img)


## A design button: `kind` is "", "primary", "ghost" or "big".
static func button(text: String, px: int, height: float, kind := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(maxf(48.0, height), maxf(48.0, height))
	b.add_theme_font_size_override("font_size", px)
	match kind:
		"primary":
			b.theme_type_variation = "PrimaryButton"
		"ghost":
			b.theme_type_variation = "GhostButton"
		"big":
			b.theme_type_variation = "BigButton"
	return b


## A white panel with an ink border and a coloured title band, used by the
## coach and the dividend panel. Returns the PanelContainer; `band` receives
## the header row so callers can add the title label into it.
static func deed_panel(band_color: Color, title: String, band_text: Color = Color.WHITE) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", card_box(Companies.PANEL, 14, 5))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = band_color
	band_style.corner_radius_top_left = 12
	band_style.corner_radius_top_right = 12
	band_style.set_content_margin_all(16)
	band_style.border_color = Companies.INK
	band_style.border_width_bottom = 2
	band.add_theme_stylebox_override("panel", band_style)
	column.add_child(band)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", display_font())
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", band_text)
	band.add_child(title_label)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 22)
	body.add_theme_constant_override("margin_right", 22)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 18)
	column.add_child(body)
	return {"panel": panel, "title": title_label, "body": body, "band": band}
