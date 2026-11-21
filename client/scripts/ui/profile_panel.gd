class_name ProfilePanel
extends Control
## The player's profile, opened from the avatar in the lobby HUD: a full
## screen in the lobby's purple room. The hero is the investor card (the
## player drawn as a share, InvestorCard) over the XP bar; under it the
## record, set like a title deed's rent table (games, wins, best finish,
## streak, then Season, Club and Look, which open their own screens), the
## Plus breakdown when the player has it, and the account: change or copy
## the name, guest or linked, link buttons.
##
## The lobby feeds it what it already holds (`apply_progress`); `open`
## fetches the rest. Every `apply_*` takes the server's dictionaries, so
## tests and screenshots feed it without a server.

signal closed
## A row or button that belongs to another screen: "season", "clubs",
## "look" (the card-back and felt picker) or "plus" (the shop).
signal navigate(to: String)
signal link_requested(provider: String)
signal rename_requested

const HERO_MIN_DP := 200.0
const HERO_MAX_DP := 420.0
const WAITING := "…"
const UNKNOWN := "—"

## Design points to px; notch (x) and home indicator (y) in px. Set both
## before the panel enters the tree.
var s := 1.85
var insets := Vector2.ZERO

var card: InvestorCard
var _room: LobbyBackdrop
var _column: VBoxContainer
var _hero: Control
var _below: Array[Control] = []
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _rows: Dictionary = {}
var _plus_panel: PanelContainer
var _plus_rows: VBoxContainer
var _plus_teaser: VBoxContainer
var _majorities: Control
var _recent: Control
var _majority_counts: Array[int] = [0, 0, 0, 0, 0, 0]
var _recent_ranks: Array[int] = []
var _account_label: Label
var _copy_button: Button
var _rename_button: Button
var _link_apple_button: Button
var _link_google_button: Button
var _close_button: Button
var _tween: Tween
var _xp_tween: Tween
var _xp := 0
## Bumped by every open, so answers to an earlier open are dropped.
var _serial := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_room = LobbyBackdrop.new()
	_room.center = Vector2(0.5, 0.22)
	add_child(_room)

	_column = VBoxContainer.new()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column.offset_left = _px(16)
	_column.offset_right = -_px(16)
	_column.offset_top = maxf(_px(14), insets.x + _px(6))
	_column.offset_bottom = -_px(12) - insets.y
	_column.add_theme_constant_override("separation", _px(10))
	add_child(_column)

	_hero = Control.new()
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.custom_minimum_size = Vector2(0, _px(HERO_MIN_DP))
	_column.add_child(_hero)
	card = InvestorCard.new()
	card.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	_hero.add_child(card)
	_hero.resized.connect(_place_card)

	var xp_row := _build_xp()
	_column.add_child(xp_row)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", _px(10))
	_scroll.add_child(_content)
	_content.add_child(_build_record())
	_content.add_child(_build_plus())
	_content.add_child(_build_account())

	_close_button = UiTheme.button("Close", _px(14), _px(48), "ghost")
	_close_button.pressed.connect(close)
	_column.add_child(_close_button)

	_below = [xp_row, _scroll, _close_button]
	resized.connect(_fit)
	_content.minimum_size_changed.connect(_fit)
	apply_progress({})
	apply_stats({})
	apply_look()
	apply_account({})
	_fit()


func _px(dp: float) -> int:
	return int(round(dp * s))


## Level, the XP bar and how far along it is, as in the lobby HUD.
func _build_xp() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8))
	_level_label = UiTheme.label("Level 1", _px(14), UiTheme.GOLD, true)
	_level_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_level_label.add_theme_constant_override("outline_size", _px(4))
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_level_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, _px(20))
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	row.add_child(_xp_bar)
	_xp_label = UiTheme.label("", _px(11), Color.WHITE, true)
	_xp_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_xp_label.add_theme_constant_override("outline_size", _px(3))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_bar.add_child(_xp_label)
	return row


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := UiTheme.card_box(Companies.PANEL, 14 * s, 4 * s, maxf(2.0, 1.5 * s))
	box.content_margin_left = 8 * s
	box.content_margin_right = 8 * s
	box.content_margin_top = 6 * s
	box.content_margin_bottom = 6 * s
	panel.add_theme_stylebox_override("panel", box)
	return panel


func _rows_box(panel: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	return box


func _add_row(parent: Control, key: String, label: String, to := "") -> LedgerRow:
	var row := LedgerRow.make(label, UNKNOWN, s, not to.is_empty())
	if not to.is_empty():
		row.pressed.connect(func() -> void: navigate.emit(to))
	parent.add_child(row)
	_rows[key] = row
	return row


func _build_record() -> Control:
	var panel := _panel()
	var box := _rows_box(panel)
	_add_row(box, "games", "Games played")
	_add_row(box, "wins", "Wins")
	_add_row(box, "best", "Best finish")
	_add_row(box, "streak", "Daily streak")
	box.add_child(_rule())
	_add_row(box, "season", "Season", "season").tooltip_text = "Season standings"
	_add_row(box, "club", "Club", "clubs").tooltip_text = "Clubs"
	_add_row(box, "look", "Look", "look").tooltip_text = "Card backs and table felts"
	return panel


## Plus: the breakdown for members, a line about it while it is on offer,
## nothing otherwise.
func _build_plus() -> Control:
	_plus_panel = _panel()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", _px(6))
	_plus_panel.add_child(stack)

	_plus_rows = VBoxContainer.new()
	_plus_rows.add_theme_constant_override("separation", 0)
	stack.add_child(_plus_rows)
	_add_row(_plus_rows, "win_rate", "Win rate")
	_add_row(_plus_rows, "average", "Average capital")
	_add_row(_plus_rows, "best_score", "Best capital")
	_add_row(_plus_rows, "podiums", "Top-three finishes")
	_add_row(_plus_rows, "people", "Games with people")
	_plus_rows.add_child(_caption("Majorities by company"))
	_majorities = Control.new()
	_majorities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_majorities.custom_minimum_size = Vector2(0, _px(44))
	_majorities.draw.connect(_draw_majorities)
	_plus_rows.add_child(_majorities)
	_plus_rows.add_child(_caption("Recent finishes, newest first"))
	_recent = Control.new()
	_recent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recent.custom_minimum_size = Vector2(0, _px(30))
	_recent.draw.connect(_draw_recent)
	_plus_rows.add_child(_recent)

	_plus_teaser = VBoxContainer.new()
	_plus_teaser.add_theme_constant_override("separation", _px(8))
	stack.add_child(_plus_teaser)
	var pitch := UiTheme.label("Plus adds your win rate, your best capital, the companies you corner most and your recent form.", _px(13))
	pitch.add_theme_font_override("font", UiTheme.body_font())
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plus_teaser.add_child(pitch)
	var see := UiTheme.button("See Plus", _px(14), _px(44))
	see.pressed.connect(func() -> void: navigate.emit("plus"))
	_plus_teaser.add_child(see)
	return _plus_panel


## A hairline between the rows that inform and the rows that lead somewhere.
func _rule() -> Control:
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(0, _px(7))
	rule.draw.connect(func() -> void:
		rule.draw_line(Vector2(6 * s, rule.size.y / 2.0), Vector2(rule.size.x - 6 * s, rule.size.y / 2.0), Color(Companies.INK, 0.18), maxf(1.0, s * 0.8)))
	return rule


func _caption(text: String) -> Label:
	var l := UiTheme.label(text, _px(12), Companies.INK_SOFT)
	l.add_theme_constant_override("line_spacing", 0)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 6 * s
	pad.content_margin_top = 8 * s
	pad.content_margin_bottom = 2 * s
	l.add_theme_stylebox_override("normal", pad)
	return l


## The account, quiet on the purple: the name's two actions, then how the
## account is kept and the link buttons where the phone can sign in.
func _build_account() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(8))
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", _px(8))
	box.add_child(names)
	_rename_button = UiTheme.button("Change name", _px(14), _px(44))
	_rename_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_button.pressed.connect(func() -> void: rename_requested.emit())
	names.add_child(_rename_button)
	_copy_button = UiTheme.button("Copy name", _px(14), _px(44))
	_copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_button.tooltip_text = "Friends add you by your name"
	_copy_button.pressed.connect(_on_copy)
	names.add_child(_copy_button)

	_account_label = UiTheme.label("", _px(13), UiTheme.LILAC)
	_account_label.add_theme_font_override("font", UiTheme.body_font())
	_account_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_account_label)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", _px(8))
	box.add_child(links)
	_link_apple_button = UiTheme.button("Link Apple", _px(14), _px(44))
	_link_apple_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_apple_button.visible = false
	_link_apple_button.pressed.connect(func() -> void: link_requested.emit("apple"))
	links.add_child(_link_apple_button)
	_link_google_button = UiTheme.button("Link Google", _px(14), _px(44))
	_link_google_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_google_button.visible = false
	_link_google_button.pressed.connect(func() -> void: link_requested.emit("google"))
	links.add_child(_link_google_button)
	return box


## The card takes the room the record leaves, between its smallest and
## largest size; on a short screen the record scrolls under it instead.
func _fit() -> void:
	if _column == null or _content == null:
		return
	var fixed := 0.0
	for c in _below:
		if c != _scroll:
			fixed += c.get_combined_minimum_size().y
	fixed += _column.get_theme_constant("separation") * _below.size()
	var room := _column.size.y - fixed - _content.get_combined_minimum_size().y
	var hero_h := clampf(room, _px(HERO_MIN_DP), _px(HERO_MAX_DP))
	if absf(_hero.custom_minimum_size.y - hero_h) > 0.5:
		_hero.custom_minimum_size.y = hero_h
	_place_card()


func _place_card() -> void:
	if card == null or _hero.size.y <= 0:
		return
	# Leave the tilt's corners and the drop shadow inside the hero.
	var room := Vector2(_hero.size.x, _hero.size.y - _px(14))
	card.size = InvestorCard.size_for(room)
	card.position = (_hero.size - card.size) / 2.0 - Vector2(0, _px(3))


## Shows the profile. `origin` is the avatar's rect on screen: the card
## grows out of it, so the player sees where the screen came from.
func open(origin := Rect2()) -> void:
	_serial += 1
	visible = true
	_scroll.scroll_vertical = 0
	card.player_name = Net.display_name
	card.show_face()
	apply_look()
	_fit()
	_play_open(origin)
	_load()


func close() -> void:
	if not visible:
		return
	_serial += 1
	if _tween != null:
		_tween.kill()
	# Out faster than in: the player is already looking at the lobby.
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		closed.emit())


func _play_open(origin: Rect2) -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	var rest := card.position
	var tilt := deg_to_rad(LogoTitle.TILT_DEG)
	card.pivot_offset = card.size / 2.0
	var from_avatar := origin.size.y > 0 and card.size.y > 0
	if from_avatar:
		card.position = origin.get_center() - _hero.global_position - card.size / 2.0
		card.scale = Vector2.ONE * (origin.size.y / card.size.y)
		card.rotation = 0.0
	else:
		card.scale = Vector2(0.9, 0.9)
		card.rotation = tilt
	for c in _below:
		c.modulate.a = 0.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if from_avatar:
		_tween.tween_property(card, "position", rest, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(card, "rotation", tilt, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var delay := 0.08
	for c in _below:
		_tween.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		delay += 0.04
	# WHY the re-place: a resize during the flight would leave the card at
	# the spot it was heading for.
	_tween.chain().tween_callback(func() -> void:
		_place_card()
		card.play_sheen())
	_fill_xp(true)


## Fetches what the lobby does not already hold. Each answer lands on its
## own; one that arrives after the profile was closed or reopened is dropped.
func _load() -> void:
	for key in ["season", "club"]:
		_rows[key].value = WAITING if Net.is_connected_to_server() else UNKNOWN
	if not Net.is_connected_to_server():
		apply_account({})
		return
	_load_stats(_serial)
	_load_season(_serial)
	_load_club(_serial)
	_load_account(_serial)


func _load_stats(serial: int) -> void:
	var data: Dictionary = await DesignerApi.stats()
	if serial == _serial:
		apply_stats(data)


func _load_season(serial: int) -> void:
	var rows: Array = await Net.season_leaderboard(1)
	if serial == _serial:
		apply_season(rows)


func _load_club(serial: int) -> void:
	var state: Dictionary = await ClubsApi.state()
	if serial == _serial:
		apply_club(state)


func _load_account(serial: int) -> void:
	var links: Dictionary = await Net.get_account_links()
	if serial == _serial:
		apply_account(links)


## The `progress` part of get_profile: level and XP, games, wins, best
## finish and the daily streak. {} shows a profile nobody has loaded yet.
func apply_progress(p: Dictionary) -> void:
	var known := not p.is_empty()
	var level := maxi(1, int(p.get("level", 1)))
	_xp = int(p.get("xp", 0))
	card.level = level
	card.player_name = Net.display_name
	_level_label.text = "Level %d" % level
	var span := Leveling.span(level)
	_xp_bar.min_value = span.x
	_xp_bar.max_value = span.y
	_xp_label.text = "%s / %s XP" % [thousands(_xp), thousands(span.y)]
	_xp_bar.tooltip_text = "%s XP to level %d" % [thousands(maxi(0, span.y - _xp)), level + 1]
	_fill_xp(false)
	var games := int(p.get("gamesPlayed", 0))
	var best := int(p.get("bestRank", 0))
	var streak := int(p.get("streak", 0))
	_rows["games"].value = thousands(games) if known else UNKNOWN
	_rows["wins"].value = thousands(int(p.get("wins", 0))) if known else UNKNOWN
	_rows["best"].value = UNKNOWN if not known else ("%s place" % ordinal(best) if best > 0 else "No games yet")
	_rows["streak"].value = UNKNOWN if not known else ("1 day" if streak == 1 else "%s days" % thousands(streak))


## The bar runs up to the player's XP when the profile opens, and steps
## there at once when the numbers change under an open profile.
func _fill_xp(animated: bool) -> void:
	if _xp_tween != null:
		_xp_tween.kill()
	if not animated or not visible:
		_xp_bar.value = _xp
		return
	_xp_bar.value = _xp_bar.min_value
	_xp_tween = create_tween()
	_xp_tween.tween_property(_xp_bar, "value", float(_xp), 0.5).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A get_stats answer. With Plus it carries the breakdown; without, the
## panel shows a line about Plus while Remote Config offers it.
func apply_stats(data: Dictionary) -> void:
	var plus := bool(data.get("plus", false))
	_plus_rows.visible = plus
	_plus_teaser.visible = not plus and RemoteConfig.plus_enabled and not data.is_empty()
	_plus_panel.visible = _plus_rows.visible or _plus_teaser.visible
	if not plus:
		return
	var games := int(data.get("games", 0))
	_rows["win_rate"].value = "%s%%" % _number(data.get("winRate", 0)) if games > 0 else UNKNOWN
	_rows["average"].value = _number(data.get("averageScore", 0)) if games > 0 else UNKNOWN
	_rows["best_score"].value = thousands(int(data.get("bestScore", 0))) if games > 0 else UNKNOWN
	_rows["podiums"].value = thousands(int(data.get("podiums", 0)))
	_rows["people"].value = thousands(int(data.get("peopleGames", 0)))
	var maj: Array = data.get("majorities", [])
	for c in 6:
		_majority_counts[c] = int(maj[c]) if c < maj.size() else 0
	_recent_ranks.clear()
	for g in data.get("recent", []).slice(0, 10):
		_recent_ranks.append(int(g.get("rank", 0)))
	_majorities.queue_redraw()
	_recent.queue_redraw()


## Rows from Net.season_leaderboard: the caller's own is marked "mine".
func apply_season(rows: Array) -> void:
	for r in rows:
		if r.get("mine", false) or r.get("userId", "") == Net.user_id:
			var rank := int(r.get("rank", 0))
			var points := "%s pts" % thousands(int(r.get("score", 0)))
			_rows["season"].value = "#%s · %s" % [thousands(rank), points] if rank > 0 else points
			return
	_rows["season"].value = "No games yet"


## A club_state answer: {club: null | {name, ...}}.
func apply_club(state: Dictionary) -> void:
	var club = state.get("club")
	var club_name := String(club.get("name", "")) if club is Dictionary else ""
	_rows["club"].value = club_name if not club_name.is_empty() else ("None yet" if not state.is_empty() else UNKNOWN)
	card.tagline = club_name if not club_name.is_empty() else "Independent investor"


## The equipped card back and felt, from Cosmetics.
func apply_look() -> void:
	_rows["look"].value = "%s · %s" % [Cosmetics.name_of(Cosmetics.card_back), Cosmetics.name_of(Cosmetics.table)]


## An account_links answer ({} offline): how the account is kept, and a
## link button for each sign-in this phone offers and the account lacks.
func apply_account(links: Dictionary) -> void:
	var online := Net.is_connected_to_server()
	var avail: Dictionary = SocialTokens.available()
	_link_apple_button.visible = bool(avail.get("apple", false)) and not links.get("apple", false)
	_link_google_button.visible = bool(avail.get("google", false)) and not links.get("google", false)
	_link_apple_button.disabled = not online
	_link_google_button.disabled = not online
	# WHY not in a room: the seat was taken under the old name, and the
	# session can only take the new one between rooms.
	_rename_button.disabled = not online or not Net.match_id.is_empty()
	_copy_button.disabled = Net.display_name.is_empty()
	var kept := Net.describe_account_links(links)
	if _link_apple_button.visible or _link_google_button.visible:
		kept += ". Link it so your progress survives a reinstall."
	_account_label.text = kept if online else "Not connected. Your record shows when you are back online."


## The name changed (the name step saved it): redraw it on the card.
func refresh_name() -> void:
	card.player_name = Net.display_name
	_copy_button.disabled = Net.display_name.is_empty()


func _on_copy() -> void:
	DisplayServer.clipboard_set(Net.display_name)
	_copy_button.text = "Copied!"
	# A tween, not a timer: it ends with the panel.
	create_tween().tween_callback(func() -> void: _copy_button.text = "Copy name").set_delay(1.4)


## Six chips in the company colours, each with how often the player held
## that company's majority, over the company's short name.
func _draw_majorities() -> void:
	var gap := 4.0 * s
	var w := (_majorities.size.x - gap * 5.0 - 12.0 * s) / 6.0
	var chip_h := 24.0 * s
	var display := UiTheme.display_font()
	var text := UiTheme.ui_font()
	for c in 6:
		var x := 6.0 * s + c * (w + gap)
		var box := StyleBoxFlat.new()
		box.bg_color = Companies.color_of(c)
		box.border_color = Companies.INK
		box.set_border_width_all(maxi(2, int(1.2 * s)))
		box.set_corner_radius_all(int(6 * s))
		box.anti_aliasing = true
		_majorities.draw_style_box(box, Rect2(x, 2 * s, w, chip_h))
		var count := compact(_majority_counts[c])
		var px := int(13 * s)
		var cw := display.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		_majorities.draw_string(display, Vector2(x + (w - cw) / 2.0, 2 * s + chip_h / 2.0 + px * 0.36), count, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.band_text_color(c))
		var short := Companies.short_name_of(c)
		var spx := int(9.5 * s)
		while spx > int(7 * s) and text.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x > w + gap:
			spx -= 1
		var sw := text.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x
		_majorities.draw_string(text, Vector2(x + (w - sw) / 2.0, 2 * s + chip_h + 12 * s), short, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, Companies.INK)


## Up to ten round chips with the place in each recent game; a win is gold.
func _draw_recent() -> void:
	var display := UiTheme.display_font()
	if _recent_ranks.is_empty():
		_recent.draw_string(UiTheme.ui_font(), Vector2(6 * s, 19 * s), "No games yet", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Companies.INK_SOFT)
		return
	var r := 11.0 * s
	var step := minf(r * 2.0 + 5.0 * s, (_recent.size.x - 12.0 * s) / 10.0)
	r = minf(r, step / 2.0 - 1.5 * s)
	for i in _recent_ranks.size():
		var c := Vector2(6 * s + r + i * step, _recent.size.y / 2.0)
		var rank := _recent_ranks[i]
		_recent.draw_circle(c, r, Companies.INK, true, -1.0, true)
		_recent.draw_circle(c, r - maxf(2.0, 1.2 * s), UiTheme.GOLD if rank == 1 else Companies.CARD_FACE, true, -1.0, true)
		var label := str(rank)
		var px := int(r * 1.05)
		var w := display.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		_recent.draw_string(display, c + Vector2(-w / 2.0, px * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)


## 1234567 -> "1,234,567".
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## A count for a narrow chip: 950, 1.2k, 12k, 3.4m.
static func compact(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 10000:
		return "%.1fk" % (floorf(n / 100.0) / 10.0)
	if n < 1000000:
		return "%dk" % int(n / 1000.0)
	return "%.1fm" % (floorf(n / 100000.0) / 10.0)


## 1 -> "1st", 2 -> "2nd", 11 -> "11th".
static func ordinal(n: int) -> String:
	var tail := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				tail = "st"
			2:
				tail = "nd"
			3:
				tail = "rd"
	return "%d%s" % [n, tail]


## A server number that may be whole or have one decimal: 26.0 -> "26",
## 12345.6 -> "12,345.6".
static func _number(v) -> String:
	var tenths := int(round(absf(float(v)) * 10.0))
	var out := thousands(tenths / 10)
	if tenths % 10 != 0:
		out += ".%d" % (tenths % 10)
	return ("-" if float(v) < 0 and tenths > 0 else "") + out
