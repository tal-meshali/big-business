class_name CountdownBurst
extends Control
## The get-ready countdown's number: 3, 2, 1, GO! drawn in the logo's gold
## (LogoTitle: toon-shaded gold face, ink outline, brown extrusion, a glint)
## over gold rays and a warm glow, the gold-on-rays look of the lobby.
## Each new value slams in like the "YOUR TURN" banner while the old one
## pops out; on the beat the glow swells and the rays kick round a step.

const RAYS := 14
const SLAM_SECONDS := 0.26
const EXIT_SECONDS := 0.14
const START_SCALE := 1.8
## How far the rays turn on each beat (half the gap between two rays), and
## how fast they settle there (per second, exponential).
const KICK := PI / RAYS
const KICK_RATE := 9.0

## Numeral size in canvas pixels (the LogoTitle px).
var px := 96.0
## The value on show ("" before the first one).
var text := ""
var _pulse := 0.0
var _angle := 0.0
var _angle_to := 0.0
var _current: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only animate while on screen.
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	resized.connect(_center)


func _ready() -> void:
	custom_minimum_size = Vector2(px * 3.4, px * 1.3)
	set_process(is_visible_in_tree())


## Shows `value`; does nothing while it is already on show, so callers can
## pass the same second every frame. Returns whether the value changed.
func show_value(value: String) -> bool:
	if value == text:
		return false
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
	holder.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	holder.scale = Vector2.ONE * START_SCALE
	holder.modulate.a = 0.0
	_current = holder
	_center()
	_pulse = 1.0
	_angle_to += KICK
	set_process(is_visible_in_tree())
	var tw := holder.create_tween().set_parallel()
	tw.tween_property(holder, "scale", Vector2.ONE, SLAM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.1)
	return true


## Clears the number (frees its LogoTitle, which glints every frame).
func reset() -> void:
	text = ""
	_current = null
	_pulse = 0.0
	for c in get_children():
		c.queue_free()


## The old value grows a little and fades as the next one lands.
func _leave(holder: Control) -> void:
	var tw := holder.create_tween().set_parallel()
	tw.tween_property(holder, "scale", Vector2.ONE * 1.2, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(holder.queue_free)


## Keeps the numerals centred; containers size this control after the
## first value may already be on show.
func _center() -> void:
	for c in get_children():
		var holder := c as Control
		if holder != null:
			holder.position = (size - holder.size) / 2.0


func _process(delta: float) -> void:
	_pulse = move_toward(_pulse, 0.0, delta * 3.0)
	_angle = lerpf(_angle, _angle_to, 1.0 - exp(-KICK_RATE * delta))
	queue_redraw()
	# Nothing moves between beats: stop redrawing until the next value.
	if _pulse <= 0.0 and absf(_angle_to - _angle) < 0.001:
		set_process(false)


func _draw() -> void:
	var c := size / 2.0
	var r := px * 2.3
	# Warm glow: stacked translucent discs, brighter in the middle, that
	# swell on each beat.
	var glow := r * (0.62 + 0.1 * _pulse)
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		draw_circle(c, glow * k, Color(1.0, 0.78, 0.24, 0.05 + 0.03 * _pulse), true, -1.0, true)
	LobbyBackdrop.draw_rays(self, c, r, _angle, RAYS, 0.34)
