class_name HelpScreen
extends Control
## Rules reference, settings and contact details, opened from the lobby's
## More sheet or the "?" button at the table. A royal sheet over the dimmed
## room, split into tabs (Goal, Turn, Market, Tokens, Scoring, Settings) so
## every page fits a phone screen without scrolling. Each rule page pairs a
## few short paragraphs with a picture of the thing it explains. Swipe
## sideways or tap a tab to change page; closing returns to wherever it
## was opened.

signal closed

## Tab order. `start_tab` in open_over() takes one of these indices.
enum Tab { GOAL, TURN, MARKET, TOKENS, SCORING, SETTINGS }

## Page slide when the tab changes, seconds.
const SLIDE := 0.2
## Finger travel (dp) that turns a sideways drag into a page change.
const SWIPE_DP := 56.0

## The rules in short, in the same words as docs/design/rules-spec.md.
## **word** is set in gold. `art` names the picture drawn on the page;
## `steps` turns the sections into numbered steps.
const PAGES := [
	{
		"tab": "Goal", "icon": "trophy", "art": "companies",
		"title": "Most capital wins",
		"sections": [
			{"body": "Collect **shares** in six companies. When the game ends, whoever holds the **most shares** of a company collects a dividend from everyone else who holds it."},
			{"title": "The companies", "body": "Each company issues a different number of shares, from **5** to **10**. The count is on every card. Five shares are set aside unseen at the start of every game."},
		],
	},
	{
		"tab": "Turn", "icon": "play", "steps": true,
		"title": "Your turn: take, then play",
		"sections": [
			{"title": "Take a share", "body": "Draw the top share of the **supply**, or pick a share from the **Market**."},
			{"title": "Play a share", "body": "Keep it in your **portfolio**, or sell it to the **Market**."},
		],
		"after": [
			{"title": "The end of the game", "body": "When the last supply share is drawn, that player finishes their turn and the game ends. Every hand joins its owner's portfolio, so the shares you are holding count."},
		],
	},
	{
		"tab": "Market", "icon": "cards", "art": "market",
		"title": "The Market",
		"sections": [
			{"title": "Drawing costs coins", "body": "Before you draw, put **1 coin** on every share in the Market, except companies whose regulator token you hold. If you can't pay, you can't draw."},
			{"title": "Taking is free", "body": "Taking a share from the Market costs nothing, and you collect **every coin** on it."},
			{"title": "Selling to the Market", "body": "A share you sell goes into the Market with no coins on it. You can't sell a share of the company you took this turn."},
		],
	},
	{
		"tab": "Tokens", "icon": "seal", "art": "token",
		"title": "Regulator tokens",
		"sections": [
			{"title": "Who holds it", "body": "Whoever has strictly the **most shares** of a company in their portfolio holds its token. On a tie the token stays where it is."},
			{"title": "What it does", "body": "You pay **nothing** onto that company's Market shares when drawing, but you **can't take** that company from the Market."},
		],
	},
	{
		"tab": "Scoring", "icon": "coins", "art": "coins",
		"title": "Dividend day",
		"sections": [
			{"body": "For each company, the sole majority holder collects **1 coin per share** from every other player who holds that company. A tie for the most pays nothing."},
			{"body": "Coins received as dividends turn **gold** and are worth **3**. Other coins are worth 1."},
			{"title": "Who wins", "body": "The most capital wins. Ties go to more gold coins, then to fewer shares in the portfolio."},
		],
	},
	{"tab": "Settings", "icon": "gear", "title": "Settings and help", "sections": []},
]

## Text on the royal sheet: cream for reading, gold for the words that matter.
const CREAM := Color("#FFF6DE")
const KEYWORD := Color("#FFC83D")

var tabs: TabStrip
var pages: Array[Control] = []
var current := 0
var _email_button: Button
var _privacy_button: Button
var _sound_button: Button
var _vibration_button: Button
var _next_button: Button
var _sheet: PanelContainer
var _page_holder: Control
var _s := 1.85
var _start_tab := 0
var _swipe_from := Vector2.INF
var _page_tween: Tween
## Whether the next tab change slides (false while opening on a start tab).
var _animate := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_s = UiTheme.layout_scale(get_viewport_rect().size)
	_build()
	select_tab(_start_tab, false)
	_play_open()


func _px(dp: float) -> int:
	return int(round(dp * _s))


func _build() -> void:
	var insets := UiTheme.safe_insets(self)
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.NIGHT, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_sheet = PanelContainer.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = _px(10)
	_sheet.offset_right = -_px(10)
	_sheet.offset_top = insets.x + _px(10)
	_sheet.offset_bottom = -insets.y - _px(10)
	var face := StyleBoxFlat.new()
	face.bg_color = UiTheme.ROYAL
	face.border_color = UiTheme.OUTLINE
	face.set_border_width_all(_px(2.5))
	face.border_width_bottom = _px(6)
	face.set_corner_radius_all(_px(22))
	face.shadow_color = Color(0, 0, 0, 0.4)
	face.shadow_size = _px(14)
	face.shadow_offset = Vector2(0, _px(6))
	face.content_margin_left = _px(14)
	face.content_margin_right = _px(14)
	face.content_margin_top = _px(14)
	face.content_margin_bottom = _px(12)
	face.anti_aliasing = true
	_sheet.add_theme_stylebox_override("panel", face)
	add_child(_sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(12))
	_sheet.add_child(column)

	var title := UiTheme.label("How Big Business works", _px(21), UiTheme.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	title.add_theme_constant_override("outline_size", _px(6))
	title.add_theme_color_override("font_shadow_color", Color("#6B2A00"))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", _px(2.5))
	title.add_theme_constant_override("shadow_outline_size", _px(6))
	column.add_child(title)

	tabs = TabStrip.new()
	var tab_list := []
	for p in PAGES:
		tab_list.append({"label": p["tab"], "icon": p["icon"]})
	tabs.setup(tab_list, _s)
	tabs.tab_selected.connect(func(i: int) -> void: _show_page(i, _animate))
	column.add_child(tabs)

	# Pages stack in one clipped box; only the current one is shown.
	_page_holder = Control.new()
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_holder.clip_contents = true
	column.add_child(_page_holder)
	for i in PAGES.size():
		var page := _build_page(PAGES[i]) if i != Tab.SETTINGS else _build_settings_page()
		page.visible = false
		_page_holder.add_child(page)
		pages.append(page)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", _px(10))
	column.add_child(footer)
	var close := UiTheme.button("Close", _px(15), _px(48), "ghost")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_help)
	footer.add_child(close)
	_next_button = UiTheme.button("Next", _px(15), _px(48), "primary")
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.size_flags_stretch_ratio = 1.4
	_next_button.pressed.connect(func() -> void: select_tab(current + 1))
	footer.add_child(_next_button)


## One rule page: a title, the picture, then short sections. A scroll box
## only matters on very short screens or with large text; on a phone the
## page fits.
func _build_page(page: Dictionary) -> ScrollContainer:
	var scroll := _page_scroll()
	var box: VBoxContainer = scroll.get_child(0)
	box.add_child(_page_title(page["title"]))
	var art := String(page.get("art", ""))
	if not art.is_empty():
		box.add_child(_art(art))
	if page.get("steps", false):
		var n := 1
		for section in page["sections"]:
			box.add_child(_step(n, section["title"], section["body"]))
			n += 1
	else:
		for section in page["sections"]:
			_add_section(box, section)
	for section in page.get("after", []):
		_add_section(box, section)
	return scroll


func _page_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", _px(14))
	scroll.add_child(box)
	return scroll


func _page_title(text: String) -> Label:
	var l := UiTheme.label(text, _px(21), Color.WHITE, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	l.add_theme_constant_override("outline_size", _px(5))
	return l


func _add_section(box: VBoxContainer, section: Dictionary) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _px(4))
	if section.has("title"):
		var h := UiTheme.label(section["title"], _px(16.5), KEYWORD, true)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		group.add_child(h)
	group.add_child(_body(section["body"]))
	box.add_child(group)


## A paragraph in cream, with **marked** words in gold.
func _body(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_override("normal_font", UiTheme.body_font())
	r.add_theme_font_override("bold_font", UiTheme.ui_font())
	r.add_theme_font_size_override("normal_font_size", _px(16.5))
	r.add_theme_font_size_override("bold_font_size", _px(16.5))
	r.add_theme_color_override("default_color", CREAM)
	r.add_theme_constant_override("line_separation", _px(2))
	r.text = markup(text)
	return r


## "**word**" to gold bold BBCode; everything else escaped as plain text.
static func markup(text: String) -> String:
	var parts := text.replace("[", "[lb]").split("**")
	var out := ""
	for i in parts.size():
		if i % 2 == 1:
			out += "[b][color=#%s]%s[/color][/b]" % [KEYWORD.to_html(false), parts[i]]
		else:
			out += parts[i]
	return out


## A numbered step on a tinted plate: gold number, title, one line.
func _step(n: int, title: String, body: String) -> PanelContainer:
	var plate := PanelContainer.new()
	var tint := StyleBoxFlat.new()
	tint.bg_color = Color(UiTheme.NIGHT, 0.45)
	tint.set_corner_radius_all(_px(16))
	tint.content_margin_left = _px(12)
	tint.content_margin_right = _px(14)
	tint.content_margin_top = _px(12)
	tint.content_margin_bottom = _px(14)
	plate.add_theme_stylebox_override("panel", tint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(12))
	plate.add_child(row)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(_px(40), _px(40))
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.draw.connect(func() -> void:
		var c := badge.size / 2.0
		var r := badge.size.x / 2.0
		badge.draw_circle(c + Vector2(0, _px(2.5)), r, UiTheme.OUTLINE)
		badge.draw_circle(c, r, UiTheme.OUTLINE)
		badge.draw_circle(c, r - _px(2.5), UiTheme.GOLD)
		badge.draw_circle(c - Vector2(0, r * 0.25), r * 0.55, Color(UiTheme.GOLD_PALE, 0.5))
		var font := UiTheme.display_font()
		var px := _px(21)
		var w := font.get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		badge.draw_string(font, c + Vector2(-w / 2.0, px * 0.36), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.OUTLINE))
	row.add_child(badge)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", _px(3))
	row.add_child(text)
	var h := UiTheme.label(title, _px(18), Color.WHITE, true)
	h.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	h.add_theme_constant_override("outline_size", _px(4))
	text.add_child(h)
	text.add_child(_body(body))
	return plate


## The picture on a rule page, drawn with the game's own cards and coins.
func _art(kind: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind:
		"companies":
			# The six companies as a small hand, smallest to largest.
			row.add_theme_constant_override("separation", _px(2))
			for c in Companies.DATA:
				var i := int(c["id"])
				row.add_child(_card(i, 0, 0.44, (i - 2.5) * 3.0, absf(i - 2.5) * _px(2.5)))
		"market":
			# A Market of three shares with coins on two of them.
			row.add_theme_constant_override("separation", _px(10))
			row.add_child(_card(1, 2, 0.56))
			row.add_child(_card(4, 0, 0.56))
			row.add_child(_card(2, 1, 0.56))
		"token":
			# The seal, and the share it keeps you from taking.
			row.add_theme_constant_override("separation", _px(22))
			row.add_child(_icon("seal", 38))
			row.add_child(_card(3, 1, 0.56, 0.0, 0.0, true))
		"coins":
			row.add_theme_constant_override("separation", _px(26))
			row.add_child(_coin(false))
			row.add_child(_coin(true))
	return row


## A face-up share for a picture, `k` times design size (scaled by dp).
func _card(company: int, coins: int, k: float, tilt_deg := 0.0, drop := 0.0, blocked := false) -> Control:
	var scale_k := k * _s
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(CardView.W, CardView.H + 6.0) * scale_k + Vector2(0, drop)
	var card := CardView.new()
	card.setup(-1, company, coins, true)
	card.blocked = blocked
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.scale = Vector2(scale_k, scale_k)
	card.pivot_offset = Vector2(CardView.W / 2.0, CardView.H)
	card.rotation_degrees = tilt_deg
	# Scale and tilt turn about the card's foot; keep its box at the holder's corner.
	card.position = Vector2(0, drop) - card.pivot_offset * (1.0 - scale_k)
	holder.add_child(card)
	return holder


func _icon(kind: String, half_dp: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(_px(half_dp * 2.2), _px(half_dp * 2.2))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void: GameIcons.draw(c, kind, c.size / 2.0, _px(half_dp)))
	return c


## A capital coin with its value, and what it is under it.
func _coin(gold: bool) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", _px(6))
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(_px(76), _px(76))
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		var at := c.size / 2.0 - Vector2(0, _px(2))
		var r := _px(33)
		var face_color := UiTheme.GOLD if gold else Companies.BRONZE
		c.draw_circle(at + Vector2(0, _px(4)), r, UiTheme.OUTLINE)
		c.draw_circle(at, r, UiTheme.OUTLINE)
		c.draw_circle(at, r - _px(2.5), face_color)
		c.draw_arc(at, r * 0.7, 0, TAU, 32, face_color.darkened(0.25), _px(2), true)
		c.draw_circle(at - Vector2(r * 0.34, r * 0.34), r * 0.2, Color(1, 1, 1, 0.45))
		var font := UiTheme.display_font()
		var px := _px(28)
		var label := "3" if gold else "1"
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var p := at + Vector2(-w / 2.0, px * 0.36)
		c.draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(4), UiTheme.OUTLINE)
		c.draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE))
	box.add_child(c)
	var caption := UiTheme.label("Gold: worth 3" if gold else "Bronze: worth 1", _px(13.5), UiTheme.LILAC, true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	return box


## Sound and vibration switches, contact links and the version.
func _build_settings_page() -> ScrollContainer:
	var scroll := _page_scroll()
	var box: VBoxContainer = scroll.get_child(0)
	box.add_child(_page_title("Settings"))
	Sfx.load_settings()
	_sound_button = _switch_row(box, "Sound", _on_toggle_sound)
	_vibration_button = _switch_row(box, "Vibration", _on_toggle_vibration)
	_refresh_toggles()

	var gap := Control.new()
	gap.custom_minimum_size.y = _px(6)
	box.add_child(gap)
	box.add_child(_page_title("Help and privacy"))
	box.add_child(_body("During a game, tap another player's seat to **mute**, **report** or **block** them. Reports go to our moderators."))
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", _px(10))
	box.add_child(links)
	_email_button = _link_button(links, "Email support", func() -> void: OS.shell_open("mailto:" + AppInfo.SUPPORT_EMAIL))
	_email_button.disabled = AppInfo.SUPPORT_EMAIL.is_empty()
	_privacy_button = _link_button(links, "Privacy policy", func() -> void: OS.shell_open(AppInfo.PRIVACY_URL))
	_privacy_button.disabled = AppInfo.PRIVACY_URL.is_empty()
	var version := UiTheme.label("Big Business %s" % AppInfo.version(), _px(12), UiTheme.LILAC)
	version.add_theme_font_override("font", UiTheme.body_font())
	box.add_child(version)
	return scroll


## A row with a name on the left and an On / Off switch button on the right.
func _switch_row(box: VBoxContainer, text: String, handler: Callable) -> Button:
	var plate := PanelContainer.new()
	var tint := StyleBoxFlat.new()
	tint.bg_color = Color(UiTheme.NIGHT, 0.45)
	tint.set_corner_radius_all(_px(16))
	tint.content_margin_left = _px(14)
	tint.content_margin_right = _px(8)
	tint.content_margin_top = _px(6)
	tint.content_margin_bottom = _px(6)
	plate.add_theme_stylebox_override("panel", tint)
	box.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	plate.add_child(row)
	var l := UiTheme.label(text, _px(16), Color.WHITE, true)
	l.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	l.add_theme_constant_override("outline_size", _px(4))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var b := UiTheme.button("", _px(14), _px(44), "green")
	b.custom_minimum_size.x = _px(84)
	b.pressed.connect(handler)
	row.add_child(b)
	return b


func _link_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := UiTheme.button(text, _px(13), _px(44))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func tab_count() -> int:
	return PAGES.size()


## Shows page `i` and moves the tab pill to it.
func select_tab(i: int, animate := true) -> void:
	i = clampi(i, 0, PAGES.size() - 1)
	if tabs.current != i:
		# The strip emits tab_selected, which shows the page.
		_animate = animate
		tabs.select(i, animate)
		_animate = true
	else:
		tabs.select(i, false)
		_show_page(i, false)


func _show_page(i: int, animate: bool) -> void:
	var from := current
	current = i
	_next_button.visible = i < PAGES.size() - 1
	if _next_button.visible:
		_next_button.text = "Next: %s" % PAGES[i + 1]["tab"]
	for p in pages.size():
		pages[p].visible = p == i
	var page: Control = pages[i]
	(page as ScrollContainer).scroll_vertical = 0
	if _page_tween != null:
		_page_tween.kill()
	_shift(page, 0.0)
	page.modulate.a = 1.0
	if not animate or from == i:
		return
	# The new page slides in from the side it comes from, and fades up.
	var dir := 1.0 if i > from else -1.0
	if is_layout_rtl():
		dir = -dir
	_shift(page, dir * _px(36))
	page.modulate.a = 0.0
	_page_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_tween.tween_method(func(x: float) -> void: _shift(page, x), dir * _px(36), 0.0, SLIDE)
	_page_tween.tween_property(page, "modulate:a", 1.0, SLIDE * 0.8)


## Moves a page sideways inside its box without changing its size.
## WHY: setting `position` on an anchored page freezes whatever width it
## had at that moment, which is wrong before the first layout.
func _shift(page: Control, x: float) -> void:
	page.offset_left = x
	page.offset_right = x


## The sheet rises a little and fades in, so it reads as one object arriving.
func _play_open() -> void:
	_sheet.pivot_offset = _sheet.size / 2.0
	_sheet.modulate.a = 0.0
	_sheet.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sheet, "modulate:a", 1.0, 0.16)
	tw.tween_property(_sheet, "scale", Vector2.ONE, 0.22)


## A sideways drag across the page turns it, like flipping a rule book.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var inside := _page_holder.get_global_rect().has_point(event.position)
		_swipe_from = event.position if inside else Vector2.INF
		return
	if _swipe_from == Vector2.INF:
		return
	var d: Vector2 = event.position - _swipe_from
	_swipe_from = Vector2.INF
	if absf(d.x) < _px(SWIPE_DP) or absf(d.x) < absf(d.y) * 1.5:
		return
	var step := -1 if d.x > 0 else 1
	if is_layout_rtl():
		step = -step
	select_tab(current + step)


func _on_toggle_sound() -> void:
	Sfx.sound_on = not Sfx.sound_on
	Sfx.save_settings()
	_refresh_toggles()


func _on_toggle_vibration() -> void:
	Sfx.vibration_on = not Sfx.vibration_on
	Sfx.save_settings()
	_refresh_toggles()


func _refresh_toggles() -> void:
	_set_switch(_sound_button, Sfx.sound_on)
	_set_switch(_vibration_button, Sfx.vibration_on)


func _set_switch(b: Button, on: bool) -> void:
	b.text = "On" if on else "Off"
	b.theme_type_variation = "GreenButton" if on else "GhostButton"
	b.add_theme_constant_override("outline_size", _px(4) if on else 0)


func close_help() -> void:
	closed.emit()
	queue_free()


## Opens the help overlay on top of `parent` at `start_tab` and returns it.
static func open_over(parent: Control, start_tab := 0) -> HelpScreen:
	var help := HelpScreen.new()
	help._start_tab = start_tab
	parent.add_child(help)
	return help
