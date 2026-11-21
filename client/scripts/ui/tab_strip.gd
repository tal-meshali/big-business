class_name TabStrip
extends Control
## A row of tabs on a sunken night track, for screens split into pages
## instead of one long scroll (the rules, the quests). The picked tab sits
## on a gold glossy pill that slides to the next pick; the others are
## lilac. Each tab has a caption and, optionally, a GameIcons icon above it.
## Tap a tab, or use left / right when the strip has focus.

signal tab_selected(index: int)

## Pill slide, seconds. Short, ease-out: it answers a tap.
const SLIDE := 0.22

## [{"label": String, "icon": String (GameIcons kind, or "")}]
var tabs: Array = []
## Design point size (px per dp).
var s := 1.85
var current := 0
## Where the pill is drawn, in tab units (animated between whole numbers).
var _pill_at := 0.0
var _tween: Tween
var _pill: GlossBox
var _track: StyleBoxFlat
var _pressed_tab := -1


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


## Sets the tabs and the scale. Call before adding to the tree.
func setup(p_tabs: Array, p_s: float) -> void:
	tabs = p_tabs
	s = p_s
	custom_minimum_size.y = (62.0 if _has_icons() else 44.0) * s
	_pill = GlossBox.make(UiTheme.GOLD, 11 * s, 3 * s, 2 * s)
	_track = StyleBoxFlat.new()
	_track.bg_color = Color(UiTheme.NIGHT, 0.6)
	_track.border_color = UiTheme.OUTLINE
	_track.set_border_width_all(maxi(2, int(2 * s)))
	_track.set_corner_radius_all(int(14 * s))
	_track.anti_aliasing = true
	queue_redraw()


func _has_icons() -> bool:
	for t in tabs:
		if not String(t.get("icon", "")).is_empty():
			return true
	return false


func tab_count() -> int:
	return tabs.size()


## Picks tab `i`; emits tab_selected when it changes.
func select(i: int, animate := true) -> void:
	i = clampi(i, 0, tabs.size() - 1)
	if _tween != null:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_pill, _pill_at, float(i), SLIDE)
	else:
		_set_pill(float(i))
	if i == current:
		return
	current = i
	tab_selected.emit(i)


func _set_pill(v: float) -> void:
	_pill_at = v
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed_tab = _tab_at(event.position.x)
		elif _pressed_tab >= 0 and _tab_at(event.position.x) == _pressed_tab:
			select(_pressed_tab)
			_pressed_tab = -1
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var step := 1 if event.is_action_pressed("ui_right") else -1
		if is_layout_rtl():
			step = -step
		select(clampi(current + step, 0, tabs.size() - 1))
		accept_event()


func _draw() -> void:
	if tabs.is_empty() or _track == null:
		return
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	draw_style_box(_pill, tab_rect(_pill_at))
	var font := UiTheme.display_font()
	var icons := _has_icons()
	for i in tabs.size():
		var r := tab_rect(i)
		# How much this tab is "picked": 1 under the pill, 0 away from it.
		var on := clampf(1.0 - absf(_pill_at - i), 0.0, 1.0)
		var label := String(tabs[i]["label"])
		var px := int((12.0 if icons else 14.0) * s)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		# Shrink a long caption to fit its slot rather than clip it.
		var room := r.size.x - 6.0 * s
		if w > room:
			px = int(px * room / w)
			w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var lip := 3.0 * s
		var base_y := r.get_center().y - lip * 0.5
		var text_y := base_y + px * 0.36
		if icons:
			var icon := String(tabs[i].get("icon", ""))
			var k := 11.5 * s
			var ic := Vector2(r.get_center().x, r.position.y + 17.0 * s)
			if not icon.is_empty():
				GameIcons.draw(self, icon, ic, k)
			text_y = r.end.y - lip - 8.0 * s
		var color := UiTheme.LILAC.lerp(UiTheme.OUTLINE, on)
		draw_string(font, Vector2(r.get_center().x - w / 2.0, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	if has_focus():
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = Color.WHITE
		ring.set_border_width_all(maxi(2, int(2 * s)))
		ring.set_corner_radius_all(int(12 * s))
		draw_style_box(ring, tab_rect(current).grow(-1.0 * s))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_LAYOUT_DIRECTION_CHANGED:
		queue_redraw()
