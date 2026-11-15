class_name IconTile
extends Button
## A tappable glossy tile with a drawn icon (GameIcons), an optional
## caption under it, and an optional red badge: the lobby dock's tabs and
## the HUD's gift and trophy. `wiggle` shakes it every few seconds to ask
## for a tap, like a reward waiting in a mobile game.

const WIGGLE_EVERY := 3.2

var icon_kind := "more"
var caption := ""
var face := UiTheme.VIOLET
## "" hides the badge; otherwise a count or "!".
var badge := "":
	set(v):
		badge = v
		queue_redraw()
var wiggle := false
## Design point size (px per dp).
var s := 1.85
var _t := 0.0
var _tile_up: GlossBox
var _tile_down: GlossBox


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _ready() -> void:
	_tile_up = GlossBox.make(face, 11 * s, 3.5 * s, 2 * s)
	_tile_down = GlossBox.make(face, 11 * s, 3.5 * s, 2 * s, true)
	tooltip_text = caption
	UiTheme.juice(self)


func _tile_rect() -> Rect2:
	var cap_h := 13.0 * s if not caption.is_empty() else 0.0
	var side := minf(size.x - 6.0 * s, size.y - cap_h - 2.0 * s)
	return Rect2(Vector2((size.x - side) / 2.0, 0), Vector2(side, side))


func _process(delta: float) -> void:
	if not wiggle:
		if rotation != 0.0:
			rotation = 0.0
		return
	_t += delta
	var p := fposmod(_t, WIGGLE_EVERY)
	pivot_offset = size / 2.0
	rotation = sin(p * 28.0) * 0.16 * maxf(0.0, 1.0 - p / 0.55) if p < 0.55 else 0.0


func _draw() -> void:
	var r := _tile_rect()
	var down := is_pressed() or button_pressed and toggle_mode
	var box := _tile_down if down else _tile_up
	if disabled:
		modulate = Color(1, 1, 1, 0.55)
	else:
		modulate = Color.WHITE
	draw_style_box(box, r)
	var lip := 3.5 * s
	var face_c := r.get_center() + Vector2(0, (lip * 0.5 - 2) if down else -lip * 0.5)
	GameIcons.draw(self, icon_kind, face_c, r.size.x * 0.27)
	if not caption.is_empty():
		var font := UiTheme.display_font()
		var sz := int(9.5 * s)
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var p := Vector2((size.x - w) / 2.0, r.end.y + 11.0 * s)
		draw_string_outline(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, int(3 * s), UiTheme.OUTLINE)
		draw_string(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)
	if not badge.is_empty():
		GameIcons.badge(self, Vector2(r.end.x - 2 * s, r.position.y + 3 * s), 8.5 * s, badge, UiTheme.display_font())
