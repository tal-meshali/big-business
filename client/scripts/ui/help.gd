class_name HelpScreen
extends Control
## Rules reference, settings and contact details, opened from the lobby's
## More sheet or the "?" button at the table. A royal sheet over the dimmed
## room, split into tabs (Goal, Turn, Market, Tokens, Scoring, Settings) so
## every page fits a phone screen without scrolling. Each rule page pairs a
## few short paragraphs with a picture of the thing it explains. Drag the
## page sideways or tap a tab to change page; Next walks forward and
## becomes Done on the last page. Closing returns to wherever it was
## opened.

signal closed

## Tab order. `start_tab` in open_over() takes one of these indices.
enum Tab { GOAL, TURN, MARKET, TOKENS, SCORING, SETTINGS }

## Page slide when the tab changes, seconds.
const SLIDE := 0.2
## Closing fade, seconds: exits are quicker than entrances.
const CLOSE := 0.14
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
			{"title": "Selling to the Market", "body": "A share you sell goes into the Market with no coins on it. If you took a share from the Market this turn, you can't sell a share of that company back. A share drawn from the supply can be sold right away."},
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
	{"tab": "Settings", "icon": "gear", "title": "Settings", "sections": []},
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
var _page_tween: Tween
var _closing := false
## A finger on the page: where it went down, when, and whether it is
## dragging the page sideways yet.
var _swipe_from := Vector2.INF
var _swipe_at := 0
var _dragging := false
## True for the rest of the frame after a drag turned or moved the page, so
## a button under the finger does not also fire on that release.
var _swiped := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_s = UiTheme.layout_scale(get_viewport_rect().size)
	_build()
	select_tab(_start_tab, false)
	_play_open()
	# WHY: on Android, back would otherwise also quit the app; here it
	# closes the sheet. Put back when the sheet goes.
	get_tree().quit_on_go_back = false
	tree_exiting.connect(func() -> void: get_tree().quit_on_go_back = true)


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
	_sheet.add_theme_stylebox_override("panel", UiTheme.royal_sheet_style(_s))
	add_child(_sheet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(14))
	_sheet.add_child(column)

	# The tabs are the header: each page's own title says what it is.
	tabs = TabStrip.new()
	var tab_list := []
	for p in PAGES:
		tab_list.append({"label": p["tab"], "icon": p["icon"]})
	tabs.setup(tab_list, _s)
	tabs.tab_selected.connect(func(i: int) -> void: _show_page(i, true))
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
	# Next walks the pages; on the last one it becomes Done, so the footer
	# never changes shape under the thumb.
	_next_button = UiTheme.button("Next", _px(15), _px(48), "primary")
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.size_flags_stretch_ratio = 1.4
	_next_button.pressed.connect(func() -> void:
		if current < PAGES.size() - 1:
			select_tab(current + 1)
		else:
			close_help())
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
	box.add_theme_constant_override("separation", _px(16))
	scroll.add_child(box)
	return scroll


func _page_title(text: String) -> Label:
	var l := UiTheme.outlined(text, _px(25))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _add_section(box: VBoxContainer, section: Dictionary) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _px(4))
	if section.has("title"):
		var h := UiTheme.outlined(section["title"], _px(20))
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
	r.add_theme_font_size_override("normal_font_size", _px(17.5))
	r.add_theme_font_size_override("bold_font_size", _px(17.5))
	r.add_theme_color_override("default_color", CREAM)
	r.add_theme_constant_override("line_separation", _px(2.5))
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


## A numbered step on a sunk plate: gold number, title, one line.
func _step(n: int, title: String, body: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate_style(_s))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(12))
	plate.add_child(row)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(_px(42), _px(42))
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.draw.connect(func() -> void:
		var c := badge.size / 2.0
		var r := badge.size.x / 2.0
		badge.draw_circle(c + Vector2(0, _px(2.5)), r, UiTheme.OUTLINE)
		badge.draw_circle(c, r, UiTheme.OUTLINE)
		badge.draw_circle(c, r - _px(2.5), UiTheme.GOLD)
		badge.draw_circle(c - Vector2(0, r * 0.25), r * 0.55, Color(UiTheme.GOLD_PALE, 0.5))
		var font := UiTheme.display_font()
		var px := _px(22)
		var w := font.get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		badge.draw_string(font, c + Vector2(-w / 2.0, px * 0.36), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.OUTLINE))
	row.add_child(badge)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", _px(3))
	row.add_child(text)
	text.add_child(UiTheme.outlined(title, _px(20)))
	text.add_child(_body(body))
	return plate


## The picture on a rule page, drawn with the game's own cards and coins.
## Sized to fill a phone page: the picture is what makes the rule stick.
func _art(kind: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind:
		"companies":
			# The six companies as a hand, smallest to largest, overlapping
			# like cards held in a fan: the count and colour stay in view.
			# Six cards each 76% visible inside the page (screen less the
			# sheet's margins and padding, 48 dp), plus what the outer cards'
			# 10 degree tilt adds on each side (sin 10 deg of their height).
			var room := get_viewport_rect().size.x - _px(48 + 8)
			var k := minf(0.58, room / (_s * (CardView.W * (1.0 + 5.0 * 0.76) + 2.0 * 0.18 * CardView.H)))
			row.add_theme_constant_override("separation", -int(CardView.W * k * _s * 0.24))
			for c in Companies.DATA:
				var i := int(c["id"])
				row.add_child(_card(i, 0, k, (i - 2.5) * 4.0, absf(i - 2.5) * absf(i - 2.5) * _px(1.6)))
		"market":
			# A Market of three shares with coins on two of them.
			row.add_theme_constant_override("separation", _px(12))
			row.add_child(_card(1, 2, 0.7))
			row.add_child(_card(4, 0, 0.7))
			row.add_child(_card(2, 1, 0.7))
		"token":
			# The seal, and the share it keeps you from taking.
			row.add_theme_constant_override("separation", _px(28))
			row.add_child(_icon("seal", 54))
			row.add_child(_card(3, 1, 0.85, 0.0, 0.0, true))
		"coins":
			row.add_theme_constant_override("separation", _px(36))
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
	box.add_theme_constant_override("separation", _px(8))
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(_px(100), _px(100))
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		var at := c.size / 2.0 - Vector2(0, _px(3))
		GameIcons.coin_face(c, at, _px(44), UiTheme.GOLD if gold else Companies.BRONZE, _px(3))
		var font := UiTheme.display_font()
		var px := _px(36)
		var label := "3" if gold else "1"
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var p := at + Vector2(-w / 2.0, px * 0.36)
		c.draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(5), UiTheme.OUTLINE)
		c.draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE))
	box.add_child(c)
	var caption := UiTheme.label("Bronze: worth 1" if not gold else "Gold: worth 3", _px(14), UiTheme.LILAC, true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	return box


## Sound and vibration switches, contact links and the version.
func _build_settings_page() -> ScrollContainer:
	var scroll := _page_scroll()
	var box: VBoxContainer = scroll.get_child(0)
	box.add_child(_page_title("Settings"))
	Sfx.load_settings()
	_sound_button = _switch_row(box, "Sound", _unless_swiped(_on_toggle_sound))
	_vibration_button = _switch_row(box, "Vibration", _unless_swiped(_on_toggle_vibration))
	_refresh_toggles()

	var gap := Control.new()
	gap.custom_minimum_size.y = _px(6)
	box.add_child(gap)
	box.add_child(_page_title("Help and privacy"))
	box.add_child(_body("During a game, tap another player's seat to **mute**, **report** or **block** them. Reports go to our moderators."))
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", _px(10))
	box.add_child(links)
	_email_button = _link_button(links, "Email support", _unless_swiped(func() -> void: OS.shell_open("mailto:" + AppInfo.SUPPORT_EMAIL)))
	# A link with nothing behind it yet is left out rather than shown greyed.
	_email_button.visible = not AppInfo.SUPPORT_EMAIL.is_empty()
	_privacy_button = _link_button(links, "Privacy policy", _unless_swiped(func() -> void: OS.shell_open(AppInfo.PRIVACY_URL)))
	_privacy_button.visible = not AppInfo.PRIVACY_URL.is_empty()
	var version := UiTheme.label("Big Business %s" % AppInfo.version(), _px(13), UiTheme.LILAC)
	version.add_theme_font_override("font", UiTheme.body_font())
	box.add_child(version)
	return scroll


## Wraps a page button's handler so a sideways drag that starts on the
## button turns the page without also pressing it.
func _unless_swiped(handler: Callable) -> Callable:
	return func() -> void:
		if not _swiped:
			handler.call()


## A row with a name on the left and an On / Off switch button on the right.
func _switch_row(box: VBoxContainer, text: String, handler: Callable) -> Button:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate_style(_s, 14, 8, 6, 6))
	box.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	plate.add_child(row)
	var l := UiTheme.outlined(text, _px(18))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var b := UiTheme.button("", _px(15), _px(46), "green")
	b.custom_minimum_size.x = _px(88)
	b.pressed.connect(handler)
	row.add_child(b)
	return b


func _link_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := UiTheme.button(text, _px(14), _px(46))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func tab_count() -> int:
	return PAGES.size()


## Shows page `i` and moves the tab pill to it.
func select_tab(i: int, animate := true) -> void:
	i = clampi(i, 0, PAGES.size() - 1)
	tabs.select(i, animate)
	_show_page(i, animate)


func _show_page(i: int, animate: bool) -> void:
	var from := current
	var from_x := pages[from].offset_left if from < pages.size() else 0.0
	current = i
	_next_button.text = "Next: %s" % PAGES[i + 1]["tab"] if i < PAGES.size() - 1 else "Done"
	for p in pages.size():
		pages[p].visible = p == i
	var page: Control = pages[i]
	(page as ScrollContainer).scroll_vertical = 0
	if _page_tween != null:
		_page_tween.kill()
	for p in pages:
		_shift(p, 0.0)
	page.modulate.a = 1.0
	if not animate:
		return
	if from == i:
		# A drag that did not turn the page springs back.
		if absf(from_x) > 0.5:
			_shift(page, from_x)
			_page_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_page_tween.tween_method(func(x: float) -> void: _shift(page, x), from_x, 0.0, SLIDE)
		return
	var dir := 1.0 if i > from else -1.0
	if is_layout_rtl():
		dir = -dir
	if absf(from_x) > 0.5:
		# Let go mid-drag: carry on from where the finger left the page.
		# The old page keeps going off the side and the new one follows it
		# in, one page-width apart, so nothing jumps on release.
		var old: Control = pages[from]
		var w := _page_holder.size.x
		old.visible = true
		_page_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_page_tween.tween_method(func(x: float) -> void:
			_shift(old, x)
			_shift(page, x + dir * w), from_x, -dir * w, SLIDE)
		_page_tween.tween_callback(func() -> void:
			old.visible = false
			_shift(old, 0.0))
		return
	# A tab tap: the new page slides in a little from its side, and fades up.
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
	modulate.a = 0.0
	_sheet.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.tween_property(_sheet, "scale", Vector2.ONE, 0.22)


## The page follows a sideways drag and turns when let go far enough (or
## flicked); at the first and last page it gives a little and springs back.
## WHY _input: the page's ScrollContainer and its text take the touches,
## so the sheet watches them on the way in, without consuming any, and
## only for presses that start on the page itself.
func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var inside := _page_holder.get_global_rect().has_point(event.position)
			_swipe_from = event.position if inside else Vector2.INF
			_swipe_at = Time.get_ticks_msec()
			_dragging = false
			return
		if _swipe_from == Vector2.INF:
			return
		var d: Vector2 = event.position - _swipe_from
		var quick := Time.get_ticks_msec() - _swipe_at < 250
		var was_dragging := _dragging
		_swipe_from = Vector2.INF
		_dragging = false
		if was_dragging:
			_swiped = true
			(func() -> void: _swiped = false).call_deferred()
		var far := absf(d.x) >= minf(_px(SWIPE_DP), _page_holder.size.x * 0.3)
		var flick := quick and absf(d.x) >= _px(24)
		var sideways := absf(d.x) >= absf(d.y) * 1.5
		var target := current + _swipe_step(d.x)
		if sideways and (far or flick) and target >= 0 and target < PAGES.size():
			select_tab(target)
		elif was_dragging:
			_show_page(current, true)
	elif event is InputEventMouseMotion and _swipe_from != Vector2.INF:
		var d: Vector2 = event.position - _swipe_from
		if not _dragging and absf(d.x) > _px(10) and absf(d.x) > absf(d.y) * 1.5:
			_dragging = true
			# A new drag during a page slide: settle the slide first, so the
			# page leaving does not freeze half on screen.
			if _page_tween != null:
				_page_tween.kill()
			for p in pages.size():
				pages[p].visible = p == current
				pages[p].modulate.a = 1.0
				_shift(pages[p], 0.0)
		if _dragging:
			var target := current + _swipe_step(d.x)
			# Past the first or last page the page only gives a little.
			var x := d.x if target >= 0 and target < PAGES.size() else d.x * 0.3
			if _page_tween != null:
				_page_tween.kill()
			pages[current].modulate.a = 1.0
			_shift(pages[current], x)


## Which way a sideways drag of `dx` turns: +1 next page, -1 previous.
func _swipe_step(dx: float) -> int:
	var step := -1 if dx > 0 else 1
	return -step if is_layout_rtl() else step


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


## The phone's back gesture or button closes the sheet, like any overlay.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		close_help()


## Closes the sheet: a quick fade and settle, faster than it opened.
func close_help() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.pivot_offset = _sheet.size / 2.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, CLOSE)
	tw.tween_property(_sheet, "scale", Vector2(0.98, 0.98), CLOSE)
	tw.chain().tween_callback(queue_free)


## Opens the help overlay on top of `parent` at `start_tab` and returns it.
static func open_over(parent: Control, start_tab := 0) -> HelpScreen:
	var help := HelpScreen.new()
	help._start_tab = start_tab
	parent.add_child(help)
	return help
