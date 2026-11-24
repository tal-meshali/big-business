class_name InvestorCard
extends Button
## The player as a share: a title-deed card like the six companies', with
## the level where a company prints its share count, the player's name on
## the gold band, their avatar in the art window and their club (or
## "Independent investor") on the name line. The hero of the profile and of
## the name step at first launch. A tap turns it over to the card back the
## player has equipped.
##
## Drawn in the units of CardView (120 x 168) times `u`, at real pixel sizes
## so the lettering stays sharp at any size.

const UNITS := Vector2(120.0, 168.0)
const INSET := 6.0
const BAND_H := 42.0
const FOOT_H := 14.0
const RADIUS := 11.0
const FLIP_OUT := 0.16
const FLIP_IN := 0.2
const SHEEN_SECONDS := 0.55

var player_name := "":
	set(v):
		player_name = v
		queue_redraw()
var level := 1:
	set(v):
		level = maxi(1, v)
		queue_redraw()
## The line under the band: the player's club, or a stand-in.
var tagline := "Independent investor":
	set(v):
		tagline = v
		queue_redraw()
var face_up := true
## Fill of the avatar disc (the local player's colour at the table).
var avatar_color := SeatView.AVATARS[0]

var _back: CardView
## The back is drawn in CardView's own 120 x 168 units; this viewport
## renders it at the card's real size, so its lettering stays as sharp as
## the face's.
var _back_port: SubViewport
var _back_view: TextureRect
var _flip: Tween
## 0..1 while the light sweeps across the face; above 1 it is off.
var _sheen := 2.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	tooltip_text = "Your investor card. Tap to see your card back."
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_back_port = SubViewport.new()
	_back_port.size_2d_override = Vector2i(int(CardView.W), int(CardView.H))
	_back_port.size_2d_override_stretch = true
	_back_port.transparent_bg = true
	_back_port.disable_3d = true
	_back_port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_back_port)
	_back = CardView.new()
	_back.setup(-1, 0, 0, false)
	# WHY: the viewport would cut the back's own shadow into square corners;
	# this card draws the shadow for both sides.
	_back.shadow = false
	_back.size = Vector2(CardView.W, CardView.H)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_port.add_child(_back)
	_back_view = TextureRect.new()
	_back_view.texture = _back_port.get_texture()
	_back_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back_view.visible = false
	add_child(_back_view)
	resized.connect(_on_resized)
	pressed.connect(flip)


## The largest card of the right proportions that fits in `room`.
static func size_for(room: Vector2) -> Vector2:
	var w := minf(room.x, room.y * UNITS.x / UNITS.y)
	return Vector2(w, w * UNITS.y / UNITS.x)


func _unit() -> float:
	return size.x / UNITS.x


func _on_resized() -> void:
	pivot_offset = size / 2.0
	_back_port.size = Vector2i(maxi(1, int(ceil(size.x))), maxi(1, int(ceil(size.y))))
	if not face_up:
		_render_back()
	queue_redraw()


## Draws the equipped card back once into its viewport.
func _render_back() -> void:
	_back.queue_redraw()
	_back_port.render_target_update_mode = SubViewport.UPDATE_ONCE


## Turns the card over with a quick squash, like the shares in the lobby.
func flip() -> void:
	if _flip != null and _flip.is_running():
		return
	_flip = create_tween()
	_flip.tween_property(self, "scale:x", 0.0, FLIP_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip.tween_callback(func() -> void:
		face_up = not face_up
		_back_view.visible = not face_up
		if not face_up:
			_render_back()
		queue_redraw())
	_flip.tween_property(self, "scale:x", 1.0, FLIP_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Shows the face again at once (the profile opens on it every time).
func show_face() -> void:
	if _flip != null:
		_flip.kill()
	scale.x = scale.y
	face_up = true
	_back_view.visible = false
	queue_redraw()


## One pass of light across the face.
func play_sheen() -> void:
	_sheen = 0.0
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		_sheen = k
		queue_redraw(), 0.0, 1.0, SHEEN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		_sheen = 2.0
		queue_redraw())


func _draw() -> void:
	var u := _unit()
	if u <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var outer := StyleBoxFlat.new()
	outer.set_corner_radius_all(int(RADIUS * u))
	outer.bg_color = Companies.CARD_FACE
	outer.border_color = Companies.INK
	outer.set_border_width_all(maxi(2, int(round(2.0 * u))))
	outer.anti_aliasing = true
	outer.shadow_color = Color(UiTheme.NIGHT, 0.5)
	outer.shadow_size = int(7 * u)
	outer.shadow_offset = Vector2(0, 5 * u)
	draw_style_box(outer, rect)
	# The back covers the face; only the card's edge and shadow show round it.
	if not face_up:
		return

	var display := UiTheme.display_font()
	var text := UiTheme.ui_font()
	var line := maxf(1.0, 1.2 * u)

	# The gold band: level where a share prints its count, then the name.
	var band := Rect2(INSET * u, INSET * u, size.x - INSET * 2 * u, BAND_H * u)
	var band_box := StyleBoxFlat.new()
	band_box.bg_color = UiTheme.GOLD
	band_box.border_color = Companies.INK
	band_box.set_border_width_all(maxi(2, int(round(2.0 * u))))
	band_box.set_corner_radius_all(int(5 * u))
	band_box.anti_aliasing = true
	draw_style_box(band_box, band)
	var count := str(level)
	# Three digits still fit the slot a two-digit share count has.
	var count_px := _fit_px(display, count, 25.0 * u, 34.0 * u, 14.0 * u)
	draw_string(display, Vector2((INSET + 6) * u, (INSET + BAND_H / 2.0) * u + count_px * 0.36), count, HORIZONTAL_ALIGNMENT_LEFT, -1, count_px, Companies.INK)
	var count_w := display.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, count_px).x
	var left := (INSET + 6) * u + count_w + 4 * u
	var right := size.x - (INSET + 4) * u
	var mid := (left + right) / 2.0
	_centered("INVESTOR", Vector2(mid, (INSET + 13) * u), int(8 * u), Companies.INK, text, right - left)
	var shown := player_name if not player_name.is_empty() else "Your name"
	_centered(shown, Vector2(mid, (INSET + 30) * u), int(15 * u), Color(Companies.INK, 1.0 if not player_name.is_empty() else 0.45), display, right - left, int(7 * u))

	# The club line over a rule, as a company's full name.
	var name_y := (INSET + BAND_H + 4) * u
	_centered(tagline, Vector2(size.x / 2.0, name_y + 7 * u), int(11 * u), Companies.INK, text, size.x - INSET * 2 * u - 4 * u, int(8 * u))
	draw_line(Vector2(INSET * u, name_y + 16 * u), Vector2(size.x - INSET * u, name_y + 16 * u), Companies.INK, line)

	# The art window: the avatar on a sunburst medallion.
	var art := Rect2(INSET * u, name_y + 20 * u, size.x - INSET * 2 * u, size.y - name_y - (20 + FOOT_H + INSET) * u)
	var art_box := StyleBoxFlat.new()
	art_box.bg_color = UiTheme.GOLD.lerp(Color.WHITE, 0.78)
	art_box.border_color = Companies.INK
	art_box.set_border_width_all(maxi(1, int(round(u))))
	art_box.set_corner_radius_all(int(4 * u))
	art_box.anti_aliasing = true
	draw_style_box(art_box, art)
	_draw_avatar(art.get_center(), minf(art.size.x, art.size.y) * 0.5 - 3 * u, u)

	var foot_y := size.y - (INSET + FOOT_H) * u
	draw_line(Vector2(INSET * u, foot_y + 3 * u), Vector2(size.x - INSET * u, foot_y + 3 * u), Companies.INK, line)
	_centered("Level %d investor" % level, Vector2(size.x / 2.0, foot_y + 12 * u), int(10 * u), Companies.INK, text, size.x - INSET * 2 * u)

	if _sheen <= 1.0:
		_draw_sheen(u)


## A gold sunburst with the avatar disc and the player's initial on it.
func _draw_avatar(c: Vector2, r: float, u: float) -> void:
	var rays := 12
	for i in rays:
		var a := TAU * i / rays - PI / 2.0
		var w := TAU / rays * 0.25
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - w) * r, c + Vector2.from_angle(a + w) * r]), Color(UiTheme.GOLD, 0.55))
	var disc := r * 0.62
	draw_circle(c + Vector2(0, 2 * u), disc + 2.2 * u, Companies.INK, true, -1.0, true)
	draw_circle(c, disc + 2.2 * u, Companies.INK, true, -1.0, true)
	draw_circle(c, disc + 1.0 * u, Color.WHITE, true, -1.0, true)
	draw_circle(c, disc - 1.2 * u, avatar_color, true, -1.0, true)
	var initial := player_name.strip_edges().substr(0, 1).to_upper() if not player_name.strip_edges().is_empty() else "?"
	var font := UiTheme.display_font()
	var px := int(disc * 1.05)
	var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(font, c + Vector2(-w / 2.0, px * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.OUTLINE)


## A slanted streak of light inside the card's border.
func _draw_sheen(u: float) -> void:
	var pad := 3.0 * u
	var h := size.y - pad * 2.0
	var w := size.x * 0.22
	var slant := h * 0.35
	var x := lerpf(-w - slant, size.x, _sheen)
	var top := PackedVector2Array([Vector2(x + slant, pad), Vector2(x + slant + w, pad), Vector2(x + w, pad + h), Vector2(x, pad + h)])
	# WHY rounded: a plain rectangle shows the streak past the card's corners.
	var clip := _rounded(Rect2(pad, pad, size.x - pad * 2.0, h), RADIUS * u - pad)
	for part in Geometry2D.intersect_polygons(top, clip):
		draw_colored_polygon(part, Color(1, 1, 1, 0.38))


## The outline of `rect` with its corners rounded by `r`, clockwise.
static func _rounded(rect: Rect2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers: Array[Vector2] = [rect.position + Vector2(rect.size.x - r, r), rect.end - Vector2(r, r), rect.position + Vector2(r, rect.size.y - r), rect.position + Vector2(r, r)]
	for corner in 4:
		for step in 5:
			var angle := -PI / 2.0 + (corner + step / 4.0) * PI / 2.0
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * r)
	return points


## The largest size from `px` down to `floor_px` at which `text` fits `room`.
static func _fit_px(font: Font, text: String, px: float, room: float, floor_px: float) -> int:
	var size_px := int(px)
	while size_px > int(floor_px) and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > room:
		size_px -= 1
	return size_px


## Text centred on `at`, shrunk towards `floor_px` to fit `room` and cut
## with an ellipsis when even that is too wide.
func _centered(text: String, at: Vector2, px: int, color: Color, font: Font, room: float, floor_px := 0) -> void:
	var size_px := _fit_px(font, text, px, room, floor_px if floor_px > 0 else px)
	var shown := text
	while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > room:
		shown = shown.substr(0, shown.length() - 2).strip_edges() + "…"
	var w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, at + Vector2(-w / 2.0, size_px / 3.0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
