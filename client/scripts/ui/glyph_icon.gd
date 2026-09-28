class_name GlyphIcon
extends Control
## A small drawn icon (see Glyphs) for buttons and rows: "hand" (the coach's
## tapping hand, which bobs), "speaker" and "speaker_off" (the sound toggle).

var kind: String = "hand"
var color: Color = Companies.INK
var _time := 0.0


func _init(p_kind: String = "hand", px: float = 24.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if kind == "hand" and is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.42
	match kind:
		"hand":
			var bob := -absf(sin(_time * PI)) * size.y * 0.18
			Glyphs.tap_hand(self, Vector2(c.x, c.y + size.y * 0.08 + bob), r, color)
		"speaker", "speaker_off":
			Glyphs.speaker(self, c, r, color, kind == "speaker_off")


func set_kind(p_kind: String) -> void:
	kind = p_kind
	queue_redraw()
