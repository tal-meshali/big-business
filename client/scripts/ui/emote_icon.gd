class_name EmoteIcon
extends Control
## A small emote icon drawn in code in the deed palette (ink outlines, gold
## faces, chance-orange and chest-blue accents). Replaces the emoji emotes,
## which rendered as placeholder glyphs because no emoji font is bundled.
##
## Kinds: wave (open hand), think (face with a thought bubble), laugh (wide
## smile), wow (round eyes and an "O" mouth), cry (face with a tear), clap
## (two hands with motion lines). Drawn at 40x40 and scaled to `size`.

const BASE := 40.0
const SKIN := Companies.GOLD

var kind: String = "laugh":
	set(value):
		kind = value
		queue_redraw()


func _init(p_kind: String = "laugh") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(BASE, BASE)
	size = Vector2(BASE, BASE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# All coordinates below are in the 40x40 design box.
	var s := minf(size.x, size.y) / BASE
	draw_set_transform(Vector2((size.x - BASE * s) / 2.0, (size.y - BASE * s) / 2.0), 0.0, Vector2(s, s))
	match kind:
		"wave":
			_draw_hand(Vector2(20, 24), 0.0, 1.0)
			# Motion arcs to the right of the hand.
			draw_arc(Vector2(30, 14), 6.0, -0.9, 0.5, 8, Companies.INK, 1.5, true)
			draw_arc(Vector2(30, 14), 9.5, -0.9, 0.5, 8, Companies.INK, 1.5, true)
		"think":
			_draw_face(Vector2(17, 24), 12.0)
			# Dot eyes, one raised brow, and a flat, slightly tilted mouth.
			draw_circle(Vector2(12.5, 22), 1.7, Companies.INK)
			draw_circle(Vector2(21.5, 22), 1.7, Companies.INK)
			draw_line(Vector2(19, 17.5), Vector2(24, 16.5), Companies.INK, 1.6, true)
			draw_line(Vector2(12, 29), Vector2(21, 27), Companies.INK, 1.8, true)
			# Thought bubble with a question mark.
			draw_circle(Vector2(27, 13), 1.6, Companies.INK)
			draw_circle(Vector2(30, 9), 2.2, Companies.INK)
			draw_circle(Vector2(34, 5), 5.5, Companies.INK)
			draw_circle(Vector2(34, 5), 4.3, Color.WHITE)
			_draw_text("?", Vector2(34, 6), 7, Companies.INK)
		"laugh":
			_draw_face(Vector2(20, 20), 15.0)
			# Eyes as short arcs, wide smile with a filled mouth.
			draw_arc(Vector2(14, 16), 2.8, PI, TAU, 8, Companies.INK, 1.8, true)
			draw_arc(Vector2(26, 16), 2.8, PI, TAU, 8, Companies.INK, 1.8, true)
			var mouth := PackedVector2Array()
			for i in 13:
				var a := lerpf(0.15, PI - 0.15, i / 12.0)
				mouth.append(Vector2(20, 21) + Vector2(cos(a), sin(a)) * 9.0)
			draw_colored_polygon(mouth, Companies.INK)
			draw_polyline(mouth, Companies.INK, 1.5, true)
		"wow":
			_draw_face(Vector2(20, 20), 15.0)
			_draw_eye(Vector2(14, 16), 3.2)
			_draw_eye(Vector2(26, 16), 3.2)
			draw_circle(Vector2(20, 27), 4.2, Companies.INK)
			draw_circle(Vector2(20, 27), 3.0, Companies.ALERT.lerp(Companies.INK, 0.5))
		"cry":
			_draw_face(Vector2(20, 20), 15.0)
			# Sad brows, small eyes, frown, and a blue tear.
			draw_line(Vector2(10, 12), Vector2(16, 14), Companies.INK, 1.6, true)
			draw_line(Vector2(30, 12), Vector2(24, 14), Companies.INK, 1.6, true)
			draw_circle(Vector2(14, 18), 1.8, Companies.INK)
			draw_circle(Vector2(26, 18), 1.8, Companies.INK)
			draw_arc(Vector2(20, 32), 6.0, PI + 0.4, TAU - 0.4, 10, Companies.INK, 1.8, true)
			var tear := PackedVector2Array([Vector2(27, 21), Vector2(30.5, 27), Vector2(27, 30), Vector2(23.5, 27)])
			draw_colored_polygon(tear, Companies.CHEST)
			draw_polyline(tear + PackedVector2Array([tear[0]]), Companies.INK, 1.2, true)
		"clap":
			_draw_hand(Vector2(13, 25), -0.5, 0.8)
			_draw_hand(Vector2(27, 25), 0.5, 0.8)
			# Motion lines between the hands.
			for i in 3:
				var y := 6.0 + i * 5.0
				draw_line(Vector2(20, y), Vector2(20, y + 2.5), Companies.CHANCE, 2.0, true)
			draw_line(Vector2(12, 8), Vector2(14, 11), Companies.CHANCE, 2.0, true)
			draw_line(Vector2(28, 8), Vector2(26, 11), Companies.CHANCE, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_face(center: Vector2, r: float) -> void:
	draw_circle(center, r, Companies.INK)
	draw_circle(center, r - 1.6, SKIN)


func _draw_eye(center: Vector2, r: float) -> void:
	draw_circle(center, r, Companies.INK)
	draw_circle(center, r - 1.2, Color.WHITE)
	draw_circle(center, r - 2.2, Companies.INK)


## An open hand: a palm circle and five finger capsules fanned out around
## the top. `angle` tilts the whole hand; `scale_f` shrinks it.
func _draw_hand(palm: Vector2, angle: float, scale_f: float) -> void:
	var pr := 7.0 * scale_f
	var fingers := [
		Vector2(-1.1, -0.4), Vector2(-0.6, -1.0), Vector2(0.0, -1.15), Vector2(0.55, -1.05), Vector2(1.05, -0.65),
	]
	for f in fingers:
		var d: Vector2 = f.rotated(angle)
		var from := palm + d * pr * 0.8
		var to := palm + d * pr * 1.9
		draw_line(from, to, Companies.INK, 6.0 * scale_f, true)
		draw_circle(to, 3.0 * scale_f, Companies.INK)
		draw_line(from, to, SKIN, 3.4 * scale_f, true)
		draw_circle(to, 1.7 * scale_f, SKIN)
	draw_circle(palm, pr + 1.4, Companies.INK)
	draw_circle(palm, pr, SKIN)


func _draw_text(text: String, at: Vector2, px: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
