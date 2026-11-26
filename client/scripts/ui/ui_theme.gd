class_name UiTheme
## Builds the shared Godot Theme in code, after the "After-hours trading
## floor" direction: glossy buttons with ink outlines, royal night panels
## with cream text, Archivo Black for headings and Nunito Sans for text.
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

## Orange ring on whatever you can tap right now.
const RING := Color("#F7941D")
const CREAM := Color("#FFFDF6")
## The table's light surfaces (seat plates, the bottom bar).
## The plate of the seat whose turn it is.
const PLATE_ON := Color("#FFF1C9")
## The quieter ink, for an away player's name.
const INK_SOFT := Color("#6B6585")
## The pill behind a "bot" or "away" tag.
const TAG := Color("#D3CBF2")

## "After-hours trading floor" (2026-11): royal purple rooms, gold for the
## one main action, violet for the rest, mint for rewards, red for badges.
## Every edge and every text outline is the same deep ink.
const NIGHT := Color("#120C2E")
const ROYAL := Color("#2B1D73")
const ROYAL_GLOW := Color("#4C34C9")
const VIOLET := Color("#6A4CF0")
const GOLD := Color("#FFC83D")
const GOLD_DEEP := Color("#F09A00")
const GOLD_PALE := Color("#FFF0A0")
const MINT := Color("#26C96F")
const BADGE := Color("#FF3B55")
const LILAC := Color("#B7AEE6")
const OUTLINE := Color("#1A1238")
const DISABLED := Color("#8E8AA8")
## Capital coins (CapitalChip): copper for bronze capital, a deeper gold
## for the coin's shaded edge, and the dark rims both are minted with.
const COPPER_PALE := Color("#FFE7C4")
const COPPER := Color("#C7742E")
const COPPER_DEEP := Color("#7A3E10")
const COPPER_RIM := Color("#3A1A00")
const COIN_GOLD_DEEP := Color("#C77A00")
const COIN_GOLD_RIM := Color("#6B3A00")
## Text on the dark rooms, bars and panels: warm cream to read, lilac for
## the quieter line under it. WHY: grey text on purple looks washed out;
## both tints come from the palette instead.
const TEXT := Color("#FFF6DE")
const TEXT_SOFT := LILAC
## Sunk areas on a royal panel: text fields, list rows, empty tracks.
const WELL := Color("#170F3D")

## Type scale, in design points (see `dp`). One role per job, so the same
## kind of text is the same size on every screen:
##   TITLE    panel titles (Archivo Black, white, ink outline, hard drop)
##   HEADING  names, scores, the line that leads a row
##   BODY     sentences: prompts, coach text, sheet text (Nunito Sans Bold)
##   LABEL    second lines of a row, list details, small buttons
##   CAPTION  spaced capitals and tags; nothing on a phone goes under it
const TYPE_TITLE := 20.0
const TYPE_HEADING := 16.0
const TYPE_BODY := 14.0
const TYPE_LABEL := 13.0
const TYPE_CAPTION := 11.0

static var _cached: Theme = null
static var _night: Theme = null
static var _fonts: Dictionary = {}
static var _reduce := false
static var _reduce_checked_ms := -1
static var _icons: Dictionary = {}
## Design points to px, as last worked out by `layout_scale`.
static var _scale := 1.85
## Set to a Vector2(top, bottom) to stand in for a phone's safe-area
## insets off-device (the screenshot scripts use it); null on real runs.
static var insets_override = null


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font = ui_font()

	# Glossy game buttons: violet by default, gold for the main action,
	# cream for quiet ones (Close, Leave), mint for rewards, red for danger.
	_gloss_styles(t, "Button", VIOLET)
	_button_text(t, "Button", Color.WHITE, OUTLINE)
	t.set_font("font", "Button", display_font())
	t.set_font_size("font_size", "Button", 22)
	t.set_type_variation("PrimaryButton", "Button")
	_gloss_styles(t, "PrimaryButton", GOLD)
	t.set_type_variation("GhostButton", "Button")
	_gloss_styles(t, "GhostButton", CREAM)
	_button_text(t, "GhostButton", OUTLINE, Color(0, 0, 0, 0))
	t.set_constant("outline_size", "GhostButton", 0)
	t.set_type_variation("BigButton", "Button")
	_gloss_styles(t, "BigButton", GOLD, 18, 8)
	t.set_type_variation("GreenButton", "Button")
	_gloss_styles(t, "GreenButton", MINT)
	t.set_type_variation("DangerButton", "Button")
	_gloss_styles(t, "DangerButton", BADGE)

	# Text fields are wells sunk into the panel: night fill, cream text, a
	# gold rim and caret while typing.
	var edit := _box(WELL, OUTLINE, 3)
	edit.set_corner_radius_all(12)
	edit.content_margin_left = 16
	edit.content_margin_right = 16
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := _box(WELL, GOLD, 3)
	edit_focus.set_corner_radius_all(12)
	edit_focus.content_margin_left = 16
	edit_focus.content_margin_right = 16
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_SOFT, 0.8))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(VIOLET, 0.7))
	t.set_font_size("font_size", "LineEdit", 24)
	# Longer text (feedback) uses the same well as a one-line field.
	var area := edit.duplicate()
	area.content_margin_top = 10
	area.content_margin_bottom = 10
	t.set_stylebox("normal", "TextEdit", area)
	var area_focus := edit_focus.duplicate()
	area_focus.content_margin_top = 10
	area_focus.content_margin_bottom = 10
	t.set_stylebox("focus", "TextEdit", area_focus)
	t.set_stylebox("read_only", "TextEdit", area)
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_placeholder_color", "TextEdit", Color(TEXT_SOFT, 0.8))
	t.set_color("caret_color", "TextEdit", GOLD)
	t.set_color("selection_color", "TextEdit", Color(VIOLET, 0.7))
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))

	t.set_color("font_color", "Label", Companies.INK)
	t.set_font_size("font_size", "Label", 19)

	var track := _box(OUTLINE, OUTLINE, 2)
	track.set_corner_radius_all(8)
	track.set_content_margin_all(0)
	var fill := GlossBox.make(MINT, 6, 0, 0)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)

	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_bg)
	_menu_styles(t)
	_cached = t
	return t


## Pop-up menus, pickers, switches and tooltips in the night palette, so
## the engine's grey defaults never show.
static func _menu_styles(t: Theme) -> void:
	var menu := _box(ROYAL, OUTLINE, 3)
	menu.set_corner_radius_all(14)
	menu.border_width_bottom = 7
	menu.set_content_margin_all(8)
	menu.shadow_color = Color(0, 0, 0, 0.35)
	menu.shadow_size = 12
	menu.shadow_offset = Vector2(0, 6)
	t.set_stylebox("panel", "PopupMenu", menu)
	var row := StyleBoxFlat.new()
	row.bg_color = VIOLET
	row.set_corner_radius_all(8)
	t.set_stylebox("hover", "PopupMenu", row)
	t.set_font("font", "PopupMenu", ui_font())
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color(TEXT_SOFT, 0.6))
	# Rows about 44 dp tall: Mute, Report and Block sit next to each other.
	t.set_constant("v_separation", "PopupMenu", 48)
	t.set_constant("item_start_padding", "PopupMenu", 24)
	t.set_constant("item_end_padding", "PopupMenu", 32)

	var pick := _box(WELL, OUTLINE, 3)
	pick.set_corner_radius_all(12)
	pick.content_margin_left = 16
	var pick_on := _box(WELL, GOLD, 3)
	pick_on.set_corner_radius_all(12)
	pick_on.content_margin_left = 16
	for state in ["normal", "hover", "disabled"]:
		t.set_stylebox(state, "OptionButton", pick)
	for state in ["pressed", "hover_pressed"]:
		t.set_stylebox(state, "OptionButton", pick_on)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font("font", "OptionButton", ui_font())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(key, "OptionButton", TEXT)
		t.set_color(key, "CheckButton", TEXT)
	t.set_color("font_disabled_color", "CheckButton", Color(TEXT_SOFT, 0.6))
	t.set_constant("outline_size", "OptionButton", 0)
	t.set_constant("outline_size", "CheckButton", 0)
	t.set_font("font", "CheckButton", ui_font())
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	# WHY own switch pictures: the engine's are a few pixels wide on a phone.
	for on in [true, false]:
		for enabled in [true, false]:
			var icon_name := ("checked" if on else "unchecked") + ("" if enabled else "_disabled")
			var picture := _switch_image(on, enabled)
			t.set_icon(icon_name, "CheckButton", ImageTexture.create_from_image(picture))
			var mirrored: Image = picture.duplicate()
			mirrored.flip_x()
			t.set_icon(icon_name + "_mirrored", "CheckButton", ImageTexture.create_from_image(mirrored))

	# Sliders (the Designer's zoom): a well for the track, violet up to a
	# cream knob.
	var groove := StyleBoxFlat.new()
	groove.bg_color = WELL
	groove.set_corner_radius_all(6)
	groove.content_margin_top = 6
	groove.content_margin_bottom = 6
	var filled: StyleBoxFlat = groove.duplicate()
	filled.bg_color = VIOLET
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	for knob in ["grabber", "grabber_highlight", "grabber_disabled"]:
		t.set_icon(knob, "HSlider", dot_icon(TEXT, 40))

	# Scroll bars: a thin lilac grabber, no track, clear of the rows.
	# WHY margins on an empty track: the bar takes its width from the track
	# box, and with none it collapsed to nothing and no list showed a bar.
	var track_gap := StyleBoxEmpty.new()
	track_gap.set_content_margin_all(4)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track_gap)
		t.set_stylebox("scroll_focus", bar, track_gap)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grabber := StyleBoxFlat.new()
			grabber.bg_color = Color(LILAC, 0.45 if state == "grabber" else 0.7)
			grabber.set_corner_radius_all(4)
			grabber.content_margin_left = 4
			grabber.content_margin_right = 4
			grabber.content_margin_top = 4
			grabber.content_margin_bottom = 4
			t.set_stylebox(state, bar, grabber)

	var tip := _box(OUTLINE, OUTLINE, 0)
	tip.set_corner_radius_all(10)
	tip.set_content_margin_all(10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 20)


## A switch drawn to an image: a mint track with the knob at the far end
## when `on`, a dim track with the knob at the near end when off. The
## right-to-left picture is this one flipped.
static func _switch_image(on: bool, enabled: bool) -> Image:
	var w := 84
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := MINT if on else ROYAL.lightened(0.14)
	var knob := Color.WHITE if on else LILAC
	var r := h / 2.0
	var knob_at := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var at := Vector2(x + 0.5, y + 0.5)
			# Distance to the edge of the pill, negative inside.
			var d := Vector2(maxf(absf(at.x - w / 2.0) - (w / 2.0 - r), 0.0), at.y - r).length() - r
			var c := OUTLINE.lerp(track, clampf(-d - 3.5, 0.0, 1.0))
			var k := at.distance_to(knob_at) - (r - 7.0)
			c = c.lerp(OUTLINE, clampf(0.5 - k, 0.0, 1.0))
			c = c.lerp(knob, clampf(-k - 2.5, 0.0, 1.0))
			c.a = clampf(0.5 - d, 0.0, 1.0) * (1.0 if enabled else 0.45)
			img.set_pixel(x, y, c)
	return img


## A round swatch of `color` with the ink ring, `px` across, as a button
## icon (a company's colour next to its name).
static func dot_icon(color: Color, px: int) -> ImageTexture:
	var key := "dot%s%d" % [color.to_html(), px]
	if _icons.has(key):
		return _icons[key]
	var n := maxi(8, px)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := n / 2.0
	var ring := maxf(2.0, n * 0.12)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() - r
			var c := OUTLINE.lerp(color, clampf(-d - ring + 0.5, 0.0, 1.0))
			c.a = clampf(0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_icons[key] = ImageTexture.create_from_image(img)
	return _icons[key]


## What a dark surface hands down to the labels inside it: cream text.
## WHY a second theme: the old white deed panels (help, get-ready) still
## rely on the default ink label colour.
static func night_theme() -> Theme:
	if _night != null:
		return _night
	var t := Theme.new()
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 4)
	_night = t
	return t


## Px per design point, as last worked out by `layout_scale`; for nodes
## that take a scale (TabStrip, royal_sheet_style) instead of sizes.
static func dp_scale() -> float:
	return _scale


## Design points to px with the scale of the screen laid out last.
static func dp(v: float) -> int:
	return int(round(v * _scale))


## Design points to pixels for a viewport: the 390 dp artboard fills the
## width, unless the screen is too short for its 844 dp height.
## Space the phone's notch or Dynamic Island (top) and home indicator
## (bottom) take from the screen, in canvas units; zero off phones.
## WHY: desktop safe areas are relative to the monitor, not the window.
static func safe_insets(ci: CanvasItem) -> Vector2:
	if insets_override != null:
		return insets_override
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
	_scale = clampf(minf(viewport.x / DESIGN_W, viewport.y / DESIGN_H), 1.2, 2.6)
	return _scale


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
	if key == "display":
		# WHY: Archivo Black's word space is narrow, and the ink outline on
		# buttons and bands closes what is left ("Goodmove", "Leaveclub").
		font.spacing_space = 3
	_fonts[key] = font
	return font


## Glossy faces for every state of one button type. Pressed, the face
## sinks into its lip and the label sinks with it.
static func _gloss_styles(t: Theme, type: String, face: Color, radius := 14, lip := 6) -> void:
	t.set_stylebox("normal", type, _gloss(face, radius, lip, false))
	t.set_stylebox("hover", type, _gloss(face.lightened(0.06), radius, lip, false))
	t.set_stylebox("pressed", type, _gloss(face.lightened(0.06), radius, lip, true))
	t.set_stylebox("hover_pressed", type, _gloss(face.lightened(0.06), radius, lip, true))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	# WHY one face for every kind: a greyed gold came out a muddy tan that
	# is in no palette; off is off, whatever the button was.
	t.set_stylebox("disabled", type, _gloss(DISABLED, radius, lip, false))


static func _gloss(face: Color, radius: int, lip: int, pressed: bool) -> GlossBox:
	var g := GlossBox.make(face, radius, lip, 3, pressed)
	g.content_margin_left = 16
	g.content_margin_right = 16
	g.content_margin_top = 6 + 3 + (lip - 1 if pressed else 0)
	g.content_margin_bottom = 6 + 3 + (1 if pressed else lip)
	return g


## Label colours for a button type: white with an ink outline on colour.
static func _button_text(t: Theme, type: String, color: Color, outline_color: Color) -> void:
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(key, type, color)
	t.set_color("font_disabled_color", type, Color(color, 0.7))
	t.set_color("font_outline_color", type, outline_color)
	t.set_constant("outline_size", type, 6)


## True when the player asked the system for less motion. Animations then
## drop movement and scale but keep fades and colour changes.
## WHY cached for a couple of seconds: seats redraw every frame, and on a
## phone the query goes through the platform each time.
static func reduce_motion() -> bool:
	var now := Time.get_ticks_msec()
	if _reduce_checked_ms < 0 or now - _reduce_checked_ms > 2000:
		# WHY == 1: it returns -1 when the platform cannot tell.
		_reduce = DisplayServer.accessibility_should_reduce_animation() == 1
		_reduce_checked_ms = now
	return _reduce


## A squash on press and a springy release, so every tap feels physical.
static func juice(b: BaseButton) -> void:
	var recenter := func() -> void: b.pivot_offset = b.size / 2.0
	b.resized.connect(recenter)
	b.button_down.connect(func() -> void:
		recenter.call()
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.04, 0.92), 0.06).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))


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


## Chunky display text for anything on colour or over the room: Archivo
## Black with the ink outline and, with `drop`, a hard ink drop under it
## (titles and big numbers; small labels read cleaner without).
static func ink_outline(l: Label, px: int, drop := false) -> Label:
	var edge := maxi(3, int(round(px * 0.2)))
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", edge)
	if drop:
		l.add_theme_color_override("font_shadow_color", OUTLINE)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(2, int(round(px * 0.1))))
		l.add_theme_constant_override("shadow_outline_size", edge)
	return l


## A title or number in the display face: white (or `color`), outlined.
static func title(text: String, px: int, color: Color = Color.WHITE, drop := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return ink_outline(l, px, drop)


## Sentences: Nunito Sans Bold, wrapping, with a little extra leading
## (light text on dark needs the air). Cream for the dark surfaces; pass
## `OUTLINE` ink on the table's light ones.
static func body(text: String, px: int, color: Color = TEXT) -> Label:
	var l := label(text, px, color)
	l.add_theme_font_override("font", body_font())
	l.add_theme_constant_override("line_spacing", maxi(2, int(round(px * 0.14))))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Spaced capitals in the display face, for section names and tags.
static func caption(text: String, px: int, color: Color = TEXT_SOFT) -> Label:
	var l := label(text, px, color)
	# WHY `uppercase` and not to_upper(): text set later stays in capitals.
	l.uppercase = true
	l.add_theme_font_override("font", spaced_font(maxi(1, int(round(px * 0.09)))))
	return l


## The display face with `spacing` px between letters.
static func spaced_font(spacing: int) -> Font:
	var key := "spaced%d" % spacing
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = display_font()
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]


## A flat face with the game's ink outline: wells, pills, bars.
static func ink_box(bg: Color, radius: float, border: float = 2.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = OUTLINE
	s.set_border_width_all(int(round(border)))
	s.set_corner_radius_all(int(round(radius)))
	s.set_content_margin_all(0)
	s.anti_aliasing = true
	return s


## A panel in the night palette, used by every sheet, dialog and overlay:
## a royal body with the ink outline and a dark lip, under a glossy band in
## `band_color` carrying the title (white, outlined, with a hard drop).
## Labels inside are cream by default. Returns the same parts as
## `deed_panel`: {"panel", "title", "body", "band"}.
static func panel(band_color: Color, title_text: String) -> Dictionary:
	var edge := maxi(2, dp(1.5))
	var radius := dp(14)
	var root := PanelContainer.new()
	root.theme = night_theme()
	var shell := ink_box(ROYAL, radius, edge)
	shell.border_width_bottom = edge + dp(3)
	# WHY margins: without them the band paints over the ink edge and the
	# panel has an outline everywhere but round its title.
	shell.content_margin_left = edge
	shell.content_margin_right = edge
	shell.content_margin_top = edge
	shell.content_margin_bottom = edge + dp(3)
	shell.shadow_color = Color(0, 0, 0, 0.4)
	shell.shadow_size = dp(8)
	shell.shadow_offset = Vector2(0, dp(4))
	root.add_theme_stylebox_override("panel", shell)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	root.add_child(column)

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = band_color
	band_style.corner_radius_top_left = radius - edge
	band_style.corner_radius_top_right = radius - edge
	band_style.border_color = OUTLINE
	band_style.border_width_bottom = edge
	band_style.content_margin_left = dp(14)
	band_style.content_margin_right = dp(14)
	band_style.content_margin_top = dp(9)
	band_style.content_margin_bottom = dp(10)
	band_style.anti_aliasing = true
	band.add_theme_stylebox_override("panel", band_style)
	# The band's gloss: a lighter upper half, as on the buttons.
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = band_color.lightened(0.22)
	gloss.corner_radius_top_left = radius - edge
	gloss.corner_radius_top_right = radius - edge
	gloss.anti_aliasing = true
	band.draw.connect(func() -> void:
		band.draw_style_box(gloss, Rect2(Vector2.ZERO, Vector2(band.size.x, (band.size.y - edge) * 0.5))))
	column.add_child(band)
	var title_label := title(title_text, dp(TYPE_TITLE), Color.WHITE, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title_label)

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left", dp(14))
	content.add_theme_constant_override("margin_right", dp(14))
	content.add_theme_constant_override("margin_top", dp(12))
	content.add_theme_constant_override("margin_bottom", dp(14))
	# WHY: a panel stretched to the screen hands the extra height to its
	# content; without this a scrolling list inside collapsed to nothing.
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	return {"panel": root, "title": title_label, "body": content, "band": band}


## A boxed row on a night panel: a sunken well with an ink edge, lit violet
## when `lead` (the row to notice).
static func well(lead := false) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", well_box(lead))
	return row


## The well's box on its own, for a Label that carries its own surface.
static func well_box(lead := false) -> StyleBoxFlat:
	var face := ink_box(Color(VIOLET, 0.55) if lead else WELL, dp(10), maxi(2, dp(1.2)))
	face.content_margin_left = dp(10)
	face.content_margin_right = dp(10)
	face.content_margin_top = dp(8)
	face.content_margin_bottom = dp(8)
	return face


## A progress bar `height` px tall: a glossy fill of `color` in the ink track.
static func meter(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", GlossBox.make(color, height / 2.0, 0, 0))
	# WHY not the theme's ink track: on a well it vanished, and an empty bar
	# looked like no bar at all.
	var track := _box(ROYAL.lightened(0.14), OUTLINE, 2)
	track.set_corner_radius_all(int(height / 2.0) + 2)
	track.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", track)
	return bar


## One line of a standings list on a night panel: a medal with the place,
## the name over a quieter detail line, and the score in gold on the right.
## `lead` marks the row to notice (the winner, or you).
static func standing_row(rank: int, who: String, detail: String, score: String, lead := false) -> Control:
	var row := well(lead)
	# The place is drawn, not a Label: tests read it from here.
	row.set_meta("rank", rank)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", dp(10))
	row.add_child(line)

	var medal := Control.new()
	medal.custom_minimum_size = Vector2(dp(28), dp(28))
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metal: Color = [GOLD, Color("#D5DBEA"), Color("#E0965A")][rank - 1] if rank >= 1 and rank <= 3 else ROYAL
	medal.draw.connect(func() -> void:
		var c := medal.size / 2.0
		var r := medal.size.x / 2.0
		medal.draw_circle(c + Vector2(0, r * 0.14), r, OUTLINE)
		medal.draw_circle(c, r, OUTLINE)
		medal.draw_circle(c, r - maxf(2.0, r * 0.16), metal)
		var f := display_font()
		var px := int(r * (1.05 if rank < 10 else 0.8))
		var txt := str(rank)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		# A place in the hundreds or thousands shrinks to stay on the medal.
		var room := (r - maxf(2.0, r * 0.16)) * 1.7
		if w > room:
			px = int(px * room / w)
			w = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		medal.draw_string(f, c + Vector2(-w / 2.0, px * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, OUTLINE if rank >= 1 and rank <= 3 else TEXT_SOFT))
	line.add_child(medal)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(names)
	var name_label := label(who, dp(TYPE_HEADING), Color.WHITE if lead else TEXT, lead)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_constant_override("line_spacing", 0)
	names.add_child(name_label)
	if not detail.is_empty():
		# WHY not lilac on the lit row: on violet it falls under 4.5:1.
		var detail_label := label(detail, dp(TYPE_LABEL), Color(TEXT, 0.85) if lead else TEXT_SOFT)
		detail_label.add_theme_font_override("font", body_font())
		detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail_label.add_theme_constant_override("line_spacing", 0)
		names.add_child(detail_label)

	var total := title(score, dp(TYPE_TITLE), GOLD)
	total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(total)
	return row


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


## A design button: `kind` is "" (violet), "primary" (gold), "ghost"
## (cream), "big" (the tall gold Play), "green" (rewards) or "danger".
static func button(text: String, px: int, height: float, kind := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(maxf(48.0, height), maxf(48.0, height))
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_constant_override("outline_size", maxi(4, int(round(px * 0.3))) if kind != "ghost" else 0)
	match kind:
		"primary":
			b.theme_type_variation = "PrimaryButton"
		"ghost":
			b.theme_type_variation = "GhostButton"
		"big":
			b.theme_type_variation = "BigButton"
		"green":
			b.theme_type_variation = "GreenButton"
		"danger":
			b.theme_type_variation = "DangerButton"
	juice(b)
	return b


## The older white panel with an ink border and a coloured title band,
## still used by the rules screen and the get-ready card. Returns the PanelContainer; `band` receives
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
	# White titles get the game's ink outline, like every label on colour.
	if band_text == Color.WHITE:
		title_label.add_theme_color_override("font_outline_color", OUTLINE)
		title_label.add_theme_constant_override("outline_size", 7)
	band.add_child(title_label)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 22)
	body.add_theme_constant_override("margin_right", 22)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 18)
	column.add_child(body)
	return {"panel": panel, "title": title_label, "body": body, "band": band}


## The royal sheet that full-screen overlays sit on (rules, quests): royal
## face, ink outline with a thicker foot, a soft drop. `k` is px per dp.
static func royal_sheet_style(k: float) -> StyleBoxFlat:
	var face := StyleBoxFlat.new()
	face.bg_color = ROYAL
	face.border_color = OUTLINE
	face.set_border_width_all(int(round(2.5 * k)))
	face.border_width_bottom = int(round(6 * k))
	face.set_corner_radius_all(int(round(22 * k)))
	face.shadow_color = Color(0, 0, 0, 0.4)
	face.shadow_size = int(round(14 * k))
	face.shadow_offset = Vector2(0, round(6 * k))
	face.content_margin_left = round(14 * k)
	face.content_margin_right = round(14 * k)
	face.content_margin_top = round(14 * k)
	face.content_margin_bottom = round(12 * k)
	face.anti_aliasing = true
	return face


## A darker plate sunk into a royal sheet, for one group (a step, a row).
static func plate_style(k: float, left := 12.0, right := 14.0, top := 12.0, bottom := 14.0) -> StyleBoxFlat:
	var tint := StyleBoxFlat.new()
	tint.bg_color = Color(NIGHT, 0.45)
	tint.set_corner_radius_all(int(round(16 * k)))
	tint.content_margin_left = round(left * k)
	tint.content_margin_right = round(right * k)
	tint.content_margin_top = round(top * k)
	tint.content_margin_bottom = round(bottom * k)
	tint.anti_aliasing = true
	return tint


## A display-font label with the game's ink outline, for text on colour.
static func outlined(text: String, px: int, color: Color = Color.WHITE) -> Label:
	var l := label(text, px, color, true)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(3, int(round(px * 0.24))))
	return l
