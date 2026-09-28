class_name TimerGlow
extends Control
## Red vignette that pulses along the screen edges when the turn timer is
## about to run out. Drawn as a stack of inset rectangle outlines whose alpha
## fades toward the centre; the pulse modulates the whole thing.

const RINGS := 16
const RING_W := 6.0
const PULSE_HZ := 1.6

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.65 + 0.35 * sin(_time * TAU * PULSE_HZ)
	for i in RINGS:
		var inset := i * RING_W
		var fade := 1.0 - float(i) / RINGS
		var color := Color(Companies.ALERT, 0.9 * fade * fade * pulse)
		var rect := Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2))
		if rect.size.x <= 0 or rect.size.y <= 0:
			break
		draw_rect(rect, color, false, RING_W)
