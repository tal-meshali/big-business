class_name SeatView
extends Control
## One opponent (or the local player) at the table: avatar, name, coins,
## portfolio pips per company, regulator tokens, turn ring with timer arc.
## White panel with an ink border; the active seat gets a warm highlight.

signal seat_pressed(seat_index: int, at: Vector2)

const W := 220.0
const H := 96.0

var seat_index: int = -1
var data: Dictionary = {}
var is_active: bool = false
var is_me: bool = false
var deadline_ms: float = 0.0
var step_ms: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seat_pressed.emit(seat_index, get_global_mouse_position())


func update(p_index: int, p_data: Dictionary, p_active: bool, p_me: bool, p_deadline: float, p_step_seconds: float) -> void:
	seat_index = p_index
	data = p_data
	is_active = p_active
	is_me = p_me
	deadline_ms = p_deadline
	step_ms = p_step_seconds * 1000.0
	queue_redraw()


func _process(_delta: float) -> void:
	if is_active and deadline_ms > 0:
		queue_redraw()


func avatar_center() -> Vector2:
	return global_position + Vector2(34, H / 2.0)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var connected: bool = data.get("connected", true) or data.get("isBot", false)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Companies.HIGHLIGHT if is_active else Companies.PANEL
	panel.set_corner_radius_all(10)
	panel.border_color = Companies.INK
	panel.set_border_width_all(3 if is_active else 1.5)
	panel.shadow_color = Color(0, 0, 0, 0.18)
	panel.shadow_size = 4
	panel.shadow_offset = Vector2(0, 2)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))

	# Avatar circle with initials.
	var c := Vector2(34, H / 2.0)
	var name_text := String(data.get("name", "?"))
	var hue := float(abs(name_text.hash()) % 360) / 360.0
	var avatar_color := Color.from_hsv(hue, 0.55, 0.8)
	if not connected:
		avatar_color = avatar_color.lerp(Color.GRAY, 0.6)
	draw_circle(c, 25, Companies.INK)
	draw_circle(c, 23, avatar_color)
	var initials := name_text.substr(0, 1).to_upper()
	var iw := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_CENTER, -1, 22).x
	draw_string(font, c + Vector2(-iw / 2.0, 8), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	# Timer arc around the avatar.
	if is_active and deadline_ms > 0 and step_ms > 0:
		var remaining := (deadline_ms - Time.get_unix_time_from_system() * 1000.0) / step_ms
		remaining = clampf(remaining, 0.0, 1.0)
		var arc_color := Companies.GOLD if remaining > 0.3 else Companies.ALERT
		draw_arc(c, 29, -PI / 2, -PI / 2 + TAU * remaining, 40, arc_color, 4.0, true)
	elif is_active:
		draw_arc(c, 29, 0, TAU, 40, Companies.GOLD, 3.0, true)

	# Name + badges.
	var label := name_text
	if is_me:
		label += " (you)"
	if data.get("isBot", false):
		label += " • bot"
	elif not connected:
		label += " • away"
	draw_string(font, Vector2(68, 24), label, HORIZONTAL_ALIGNMENT_LEFT, W - 72, 17, Companies.INK if connected else Companies.INK_SOFT)

	# Coins and hand count.
	var bronze := int(data.get("bronze", 0))
	var gold := int(data.get("gold", 0))
	draw_circle(Vector2(76, 42), 8, Companies.INK)
	draw_circle(Vector2(76, 42), 6.5, Companies.BRONZE)
	draw_string(font, Vector2(88, 47), str(bronze), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Companies.INK)
	if gold > 0:
		draw_circle(Vector2(122, 42), 8, Companies.INK)
		draw_circle(Vector2(122, 42), 6.5, Companies.GOLD)
		draw_string(font, Vector2(134, 47), str(gold), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Companies.INK)
	var hand_count := int(data.get("handCount", 0))
	for i in hand_count:
		draw_rect(Rect2(W - 30 + i * 6, 34, 8, 12), Companies.CARD_FACE, true)
		draw_rect(Rect2(W - 30 + i * 6, 34, 8, 12), Companies.INK, false, 1.0)

	# Portfolio pips: one colour block per company held, like a deed's band.
	var counts := [0, 0, 0, 0, 0, 0]
	for card in data.get("portfolio", []):
		counts[int(card.get("company", 0))] += 1
	var x := 68.0
	for company in 6:
		if counts[company] == 0:
			continue
		var col := Companies.color_of(company)
		var pip := Rect2(x, 58, 22, 26)
		draw_rect(pip, col, true)
		draw_rect(pip, Companies.INK, false, 1.0)
		var txt := str(counts[company])
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		draw_string(font, Vector2(x + 11 - tw / 2.0, 77), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Companies.band_text_color(company))
		# Regulator token: small "R" ring on the pip.
		if data.get("tokens", []).has(company):
			draw_circle(Vector2(x + 20, 60), 7.5, Companies.INK)
			draw_circle(Vector2(x + 20, 60), 6, Color.WHITE)
			var rw := font.get_string_size("R", HORIZONTAL_ALIGNMENT_CENTER, -1, 9).x
			draw_string(font, Vector2(x + 20 - rw / 2.0, 63.5), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Companies.INK)
		x += 26
