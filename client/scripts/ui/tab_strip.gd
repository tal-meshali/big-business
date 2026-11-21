class_name TabStrip
extends Control
## A row of tabs on a sunken night track, for screens split into pages
## instead of one long scroll (the rules, the quests). The picked tab sits
## on a gold glossy pill that slides to the next pick; the others are
## lilac and their icons dimmed. Each tab has a caption and, optionally, a
## GameIcons icon above it. Tap a tab, or use left / right when the strip
## has keyboard focus.

## Emitted when the player picks a tab (tap or keys), not when code calls select().
signal tab_selected(index: int)

## Pill slide, seconds. Short, ease-out: it answers a tap.
const SLIDE := 0.22
## Inactive icons fade back so the picked tab leads.
const IDLE_ICON_ALPHA := 0.6

## [{"label": String, "icon": String (GameIcons kind, or "")}]
var tabs: Array = []
## Design point size (px per dp).
var s := 1.85
var current := 0
## Where the pill is drawn, in tab units (animated between whole numbers).
var _pill_at := 0.0
var _tween: Tween
var _pill: GlossBox
var _pill_down: GlossBox
var _track: StyleBoxFlat
var _ring: StyleBoxFlat
var _press: StyleBoxFlat
var _pressed_tab := -1
## One child per icon, so each can fade on its own.
var _icons: Array[Control] = []


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


## Sets the tabs and the scale. Call before adding to the tree.
func setup(p_tabs: Array, p_s: float) -> void:
	tabs = p_tabs
	s = p_s
	custom_minimum_size.y = (62.0 if _has_icons() else 46.0) * s
	_pill = GlossBox.make(UiTheme.GOLD, 11 * s, 3 * s, 2 * s)
	_pill_down = GlossBox.make(UiTheme.GOLD, 11 * s, 3 * s, 2 * s, true)
	_track = StyleBoxFlat.new()
	# Opaque, so the strip reads the same on any surface behind it.
	_track.bg_color = UiTheme.NIGHT
	_track.border_color = UiTheme.OUTLINE
	_track.set_border_width_all(maxi(2, int(2 * s)))
	_track.set_corner_radius_all(int(14 * s))
	_track.anti_aliasing = true
	_ring = StyleBoxFlat.new()
	_ring.draw_center = false
	_ring.border_color = Color.WHITE
	_ring.set_border_width_all(maxi(2, int(2 * s)))
	_ring.set_corner_radius_all(int(12 * s))
	_press = StyleBoxFlat.new()
	_press.bg_color = Color(UiTheme.ROYAL_GLOW, 0.45)
	_press.set_corner_radius_all(int(11 * s))
	_press.anti_aliasing = true
	for c in _icons:
		c.queue_free()
	_icons.clear()
	for t in tabs:
		var kind := String(t.get("icon", ""))
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.visible = not kind.is_empty()
		c.draw.connect(func() -> void:
			if not kind.is_empty():
				GameIcons.draw(c, kind, c.size / 2.0, c.size.x * 0.5))
		add_child(c)
		_icons.append(c)
	_layout_icons()


func _has_icons() -> bool:
	for t in tabs:
		if not String(t.get("icon", "")).is_empty():
			return true
	return false


func tab_count() -> int:
	return tabs.size()


## Moves the pill to tab `i`. Does not emit tab_selected: the caller
## already knows, and shows its own page.
func select(i: int, animate := true) -> void:
	i = clampi(i, 0, tabs.size() - 1)
	current = i
	if _tween != null:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_pill, _pill_at, float(i), SLIDE)
	else:
		_set_pill(float(i))


## A pick by the player: moves the pill and tells the screen.
func _pick(i: int) -> void:
	if i == current:
		return
	select(i)
	tab_selected.emit(i)


func _set_pill(v: float) -> void:
	_pill_at = v
	_layout_icons()
	queue_redraw()


## The rect of tab slot `i` (slot 0 is on the right in right-to-left).
func tab_rect(i: float) -> Rect2:
	var pad := 4.0 * s
	var n := maxi(1, tabs.size())
	var w := (size.x - pad * 2.0) / n
	var slot := (n - 1 - i) if is_layout_rtl() else i
	return Rect2(Vector2(pad + slot * w, pad), Vector2(w, size.y - pad * 2.0))


func _tab_at(x: float) -> int:
	for i in tabs.size():
		var r := tab_rect(i)
		if x >= r.position.x and x < r.end.x:
			return i
	return -1


## Places each icon over its slot, faded unless the pill is under it, and
## sunk with the face while its tab is held down.
func _layout_icons() -> void:
	var k := 11.5 * s
	for i in _icons.size():
		var r := tab_rect(i)
		var on := clampf(1.0 - absf(_pill_at - i), 0.0, 1.0)
		var sink := 2.0 * s if i == _pressed_tab else 0.0
		var c := _icons[i]
		c.size = Vector2(k * 2.0, k * 2.0)
		c.position = Vector2(r.get_center().x - k, r.position.y + 17.0 * s - k + sink)
		c.modulate.a = lerpf(IDLE_ICON_ALPHA, 1.0, on)
		c.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed_tab = _tab_at(event.position.x)
		else:
			# Like a button: letting go off the strip cancels the pick.
			var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
			var picked := _pressed_tab if inside and _tab_at(event.position.x) == _pressed_tab else -1
			_pressed_tab = -1
			if picked >= 0:
				_pick(picked)
		_layout_icons()
		queue_redraw()
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var step := 1 if event.is_action_pressed("ui_right") else -1
		if is_layout_rtl():
			step = -step
		_pick(clampi(current + step, 0, tabs.size() - 1))
		accept_event()


func _draw() -> void:
	# Nothing to draw before the first layout gives the strip a width.
	if tabs.is_empty() or _track == null or size.x < tabs.size() * 12.0 * s:
		return
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	# Feedback while a finger is down on a tab: the pill sinks, others light up.
	if _pressed_tab >= 0 and _pressed_tab != current:
		draw_style_box(_press, tab_rect(_pressed_tab))
	var pill_held := _pressed_tab == current and absf(_pill_at - current) < 0.01
	draw_style_box(_pill_down if pill_held else _pill, tab_rect(_pill_at))
	var font := UiTheme.display_font()
	var icons := _has_icons()
	for i in tabs.size():
		var r := tab_rect(i)
		# How much this tab is "picked": 1 under the pill, 0 away from it.
		var on := clampf(1.0 - absf(_pill_at - i), 0.0, 1.0)
		var label := String(tabs[i]["label"])
		var px := int((12.0 if icons else 15.0) * s)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		# Shrink a long caption to fit its slot rather than clip it.
		var room := r.size.x - 6.0 * s
		if w > room:
			px = int(px * room / w)
			w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var lip := 3.0 * s
		var sink := 2.0 * s if i == _pressed_tab else 0.0
		var text_y := r.get_center().y - lip * 0.5 + px * 0.36 + sink
		if icons:
			text_y = r.end.y - lip - 8.0 * s + sink
		var color := UiTheme.LILAC.lerp(UiTheme.OUTLINE, on)
		draw_string(font, Vector2(r.get_center().x - w / 2.0, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	# WHY has_focus(true): a tap also focuses the strip, and the ring is
	# only for keyboard and controller users, like Button's focus style.
	if has_focus(true):
		draw_style_box(_ring, tab_rect(current).grow(-1.0 * s))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_LAYOUT_DIRECTION_CHANGED:
		_layout_icons()
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
