class_name CountdownBurst
extends Control
## The get-ready countdown's number: 3, 2, 1, GO! drawn in the logo's gold
## (LogoTitle: toon-shaded gold face, ink outline, brown extrusion, a glint)
## over slow gold rays and a warm glow, the gold-on-rays look of the lobby.
## Each new value slams in like the "YOUR TURN" banner while the old one
## pops out, and the glow pulses on the beat.

const RAYS := 14
## Seconds for one full turn of the rays.
const RAY_SECONDS := 40.0
const SLAM_SECONDS := 0.26
const EXIT_SECONDS := 0.14
const START_SCALE := 1.8

## Numeral size in canvas pixels (the LogoTitle px).
var px := 96.0
## The value on show ("" before the first one).
var text := ""
var _t := 0.0
var _pulse := 0.0
var _current: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(px * 3.4, px * 1.3)


## Shows `value`; does nothing while it is already on show, so callers can
## pass the same second every frame.
func show_value(value: String) -> void:
	if value == text:
		return
	text = value
	if _current != null:
		_leave(_current)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := LogoTitle.new()
	logo.lines = [value]
	logo.sizes = [1.0]
	logo.px = px
	logo.tilt = 0.0
	holder.add_child(logo)
	add_child(holder)
	var sz := logo.get_combined_minimum_size()
	logo.size = sz
	holder.size = sz
	holder.pivot_offset = sz / 2.0
	holder.position = (size - sz) / 2.0
	holder.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	holder.scale = Vector2.ONE * START_SCALE
	holder.modulate.a = 0.0
	_current = holder
	_pulse = 1.0
	var tw := holder.create_tween().set_parallel()
	tw.tween_property(holder, "scale", Vector2.ONE, SLAM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.1)


## Clears the number, for a new countdown.
func reset() -> void:
	text = ""
	_current = null
	for c in get_children():
		c.queue_free()


## The old value grows a little and fades as the next one lands.
func _leave(holder: Control) -> void:
	var tw := holder.create_tween().set_parallel()
	tw.tween_property(holder, "scale", Vector2.ONE * 1.2, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(holder.queue_free)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_pulse = move_toward(_pulse, 0.0, delta * 3.0)
	# Containers size this control after the first value arrives: keep the
	# numerals centred on it.
	for c in get_children():
		var holder := c as Control
		if holder != null:
			holder.position = (size - holder.size) / 2.0
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := px * 2.3
	# Warm glow: stacked translucent discs, brighter in the middle, that
	# swell on each beat.
	var glow := r * (0.62 + 0.1 * _pulse)
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		draw_circle(c, glow * k, Color(1.0, 0.78, 0.24, 0.05 + 0.03 * _pulse), true, -1.0, true)
	# Rays, as in the lobby: thin gold wedges fading to nothing.
	var turn := _t / RAY_SECONDS * TAU
	var w := TAU / RAYS * 0.3
	for i in RAYS:
		var a := turn + TAU * i / RAYS
		var pts := PackedVector2Array([c, c + Vector2.from_angle(a - w) * r, c + Vector2.from_angle(a + w) * r])
		var cols := PackedColorArray([Color(1, 0.84, 0.43, 0.34), Color(1, 0.84, 0.43, 0.0), Color(1, 0.84, 0.43, 0.0)])
		draw_polygon(pts, cols)
