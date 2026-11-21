class_name ClubsPanel
extends PanelContainer
## Clubs: start a club (name picked from two word lists and a company
## crest), join an open one, and, once in a club, its members with their
## points this week and the weekly club league. Opened from the lobby.

signal closed

var _status: Label
var _content: VBoxContainer
var _adjective: OptionButton
var _noun: OptionButton
var _crest := 0
var _crest_buttons: Array[Button] = []


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.panel(UiTheme.VIOLET, "Clubs")
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.dp(8))
	deed["body"].add_child(column)
	# Loading and errors; hidden while there is nothing to say.
	_status = _label("", UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT)
	_status.visible = false
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", UiTheme.dp(6))
	scroll.add_child(_content)
	var close := _button("Close", "ghost")
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)


func _say(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func open() -> void:
	visible = true
	await refresh()


func refresh() -> void:
	_say("Loading…")
	var data: Dictionary = await ClubsApi.state()
	if data.is_empty():
		_say("Connect to see clubs." if ClubsApi.last_error.is_empty() else ClubsApi.last_error)
		return
	var listing: Dictionary = {}
	if not data.get("club") is Dictionary:
		listing = await ClubsApi.list()
	apply_state(data, listing)


## Builds the screen from club_state (and club_list when not in a club).
func apply_state(data: Dictionary, listing: Dictionary = {}) -> void:
	_say("")
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	var club = data.get("club")
	if club is Dictionary:
		_build_club(club, int(data.get("max", 30)))
	else:
		_build_start()
		_build_join(listing.get("clubs", []))
	_build_league(data.get("league", []), String(club.get("id", "")) if club is Dictionary else "")
	if club is Dictionary:
		# Last and quiet: the one button here that takes something away.
		var leave := _button("Leave club", "ghost")
		leave.pressed.connect(_on_leave)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", UiTheme.dp(10))
		pad.add_child(leave)
		_content.add_child(pad)


func _build_club(club: Dictionary, max_members: int) -> void:
	var members: Array = club.get("members", [])
	var club_name := UiTheme.title(String(club.get("name", "")), UiTheme.dp(UiTheme.TYPE_TITLE), UiTheme.GOLD)
	club_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(club_name)
	var rank := int(club.get("rank", 0))
	var standing := "%d points this week" % int(club.get("score", 0))
	if rank > 0:
		standing += ", place %d in the league" % rank
	_content.add_child(_label("%s. %d of %d members." % [standing, members.size(), max_members], UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT))
	var role := String(club.get("role", "member"))
	for m in members:
		var row := UiTheme.well(String(m.get("userId", "")) == Net.user_id and not Net.user_id.is_empty())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UiTheme.dp(8))
		line.custom_minimum_size = Vector2(0, UiTheme.dp(32))
		row.add_child(line)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(names)
		var name_label := UiTheme.label(String(m.get("name", "?")), UiTheme.dp(UiTheme.TYPE_BODY), UiTheme.TEXT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(name_label)
		if String(m.get("role", "")) != "member":
			var role_label := _label(String(m.get("role", "")).capitalize(), UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT)
			role_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			names.add_child(role_label)
		var week := UiTheme.title("%d pts" % int(m.get("week", 0)), UiTheme.dp(UiTheme.TYPE_HEADING), UiTheme.GOLD)
		week.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(week)
		if _may_remove(role, String(m.get("role", ""))) and String(m.get("userId", "")) != Net.user_id:
			var remove := _button("Remove")
			remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			remove.pressed.connect(_on_remove.bind(String(m.get("userId", ""))))
			line.add_child(remove)
		_content.add_child(row)


static func _may_remove(actor: String, target: String) -> bool:
	if actor == "owner":
		return target != "owner"
	return actor == "admin" and target == "member"


func _build_start() -> void:
	_content.add_child(_heading("Start a club"))
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", UiTheme.dp(6))
	_adjective = _picker(ClubsApi.ADJECTIVES)
	_noun = _picker(ClubsApi.NOUNS)
	names.add_child(_adjective)
	names.add_child(_noun)
	_content.add_child(names)
	_content.add_child(_label("Pick a crest", UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT))
	var crests := GridContainer.new()
	crests.columns = 3
	crests.add_theme_constant_override("h_separation", UiTheme.dp(6))
	crests.add_theme_constant_override("v_separation", UiTheme.dp(6))
	_crest_buttons.clear()
	for c in 6:
		var b := _button(Companies.short_name_of(c))
		# The company's colour beside its name: a crest is a company.
		b.icon = UiTheme.dot_icon(Companies.color_of(c), UiTheme.dp(14))
		b.add_theme_constant_override("h_separation", UiTheme.dp(5))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_crest.bind(c))
		_crest_buttons.append(b)
		crests.add_child(b)
	_content.add_child(crests)
	_on_crest(_crest)
	var create := _button("Start club", "primary")
	create.pressed.connect(_on_create)
	_content.add_child(create)


func _build_join(clubs: Array) -> void:
	_content.add_child(_heading("Join a club"))
	if clubs.is_empty():
		_content.add_child(_label("No open clubs right now. Start one!", UiTheme.TYPE_BODY, UiTheme.TEXT_SOFT))
	for c in clubs:
		var row := UiTheme.well()
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UiTheme.dp(8))
		row.add_child(line)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(names)
		var name_label := UiTheme.label(String(c.get("name", "")), UiTheme.dp(UiTheme.TYPE_BODY), UiTheme.TEXT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(name_label)
		var count := _label("%d of %d members" % [int(c.get("count", 0)), int(c.get("max", 30))], UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		names.add_child(count)
		var join := _button("Join")
		join.custom_minimum_size.x = UiTheme.dp(72)
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		join.pressed.connect(_on_join.bind(String(c.get("id", ""))))
		line.add_child(join)
		_content.add_child(row)


func _build_league(league: Array, mine: String) -> void:
	_content.add_child(_heading("This week's league"))
	if league.is_empty():
		_content.add_child(_label("No club has points yet this week. Games with other people earn points for your club.", UiTheme.TYPE_BODY, UiTheme.TEXT_SOFT))
		return
	for r in league:
		var yours: bool = String(r.get("id", "")) == mine and not mine.is_empty()
		_content.add_child(UiTheme.standing_row(int(r.get("rank", 0)), String(r.get("name", "")), "Your club" if yours else "", str(int(r.get("score", 0))), yours))


## The crest in use is gold; the rest stay violet.
func _on_crest(c: int) -> void:
	_crest = c
	for i in _crest_buttons.size():
		_crest_buttons[i].set_pressed_no_signal(i == c)
		_crest_buttons[i].theme_type_variation = "PrimaryButton" if i == c else ""


func _on_create() -> void:
	var res := await ClubsApi.create(_adjective.selected, _noun.selected, _crest)
	if res.is_empty():
		_say(ClubsApi.last_error)
		return
	await refresh()


func _on_join(club_id: String) -> void:
	if (await ClubsApi.join(club_id)).is_empty():
		_say(ClubsApi.last_error)
		return
	await refresh()


func _on_leave() -> void:
	if not await ClubsApi.leave():
		_say(ClubsApi.last_error)
		return
	await refresh()


func _on_remove(user_id: String) -> void:
	if not await ClubsApi.kick(user_id):
		_say(ClubsApi.last_error)
		return
	await refresh()


func _picker(words: Array[String]) -> OptionButton:
	var o := OptionButton.new()
	for w in words:
		o.add_item(w)
	o.custom_minimum_size = Vector2(0, UiTheme.dp(44))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", UiTheme.dp(UiTheme.TYPE_BODY))
	o.get_popup().add_theme_font_size_override("font_size", UiTheme.dp(UiTheme.TYPE_BODY))
	o.get_popup().transparent_bg = true
	return o


## A section name, with air above it to part it from the section before.
func _heading(text: String) -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", UiTheme.dp(6))
	pad.add_child(UiTheme.caption(text, UiTheme.dp(UiTheme.TYPE_CAPTION)))
	return pad


func _label(text: String, size_dp: float, color: Color = UiTheme.TEXT) -> Label:
	return UiTheme.body(text, UiTheme.dp(size_dp), color)


func _button(text: String, kind := "") -> Button:
	return UiTheme.button(text, UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.dp(44), kind)
