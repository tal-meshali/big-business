class_name ClubsPanel
extends PanelContainer
## Clubs: start a club (name picked from two word lists and a company
## crest), join an open one, and, once in a club, its members with their
## points this week and the weekly club league. Opened from the lobby.

signal closed

const ROW_HEIGHT := 48.0

var _status: Label
var _content: VBoxContainer
var _adjective: OptionButton
var _noun: OptionButton
var _crest := 0
var _crest_buttons: Array[Button] = []


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.deed_panel(Companies.CHEST, "Clubs", Color.WHITE)
	deed["title"].add_theme_font_size_override("font_size", 28)
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	deed["body"].add_child(column)
	_status = _label("", 17)
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	var close := _button("Close")
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)


func open() -> void:
	visible = true
	await refresh()


func refresh() -> void:
	_status.text = "Loading..."
	var data: Dictionary = await ClubsApi.state()
	if data.is_empty():
		_status.text = "Connect to see clubs." if ClubsApi.last_error.is_empty() else ClubsApi.last_error
		return
	var listing: Dictionary = {}
	if not data.get("club") is Dictionary:
		listing = await ClubsApi.list()
	apply_state(data, listing)


## Builds the screen from club_state (and club_list when not in a club).
func apply_state(data: Dictionary, listing: Dictionary = {}) -> void:
	_status.text = ""
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


func _build_club(club: Dictionary, max_members: int) -> void:
	var members: Array = club.get("members", [])
	_content.add_child(_heading(String(club.get("name", ""))))
	var rank := int(club.get("rank", 0))
	var standing := "%d points this week" % int(club.get("score", 0))
	if rank > 0:
		standing += ", place %d in the league" % rank
	_content.add_child(_label("%s. %d of %d members." % [standing, members.size(), max_members], 18))
	var role := String(club.get("role", "member"))
	for m in members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		var name_label := _label("%s%s" % [String(m.get("name", "?")), "" if String(m.get("role", "")) == "member" else " (%s)" % String(m.get("role", ""))], 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		row.add_child(_label("%d pts" % int(m.get("week", 0)), 18))
		if _may_remove(role, String(m.get("role", ""))) and String(m.get("userId", "")) != Net.user_id:
			var remove := _button("Remove")
			remove.custom_minimum_size = Vector2(110, ROW_HEIGHT)
			remove.pressed.connect(_on_remove.bind(String(m.get("userId", ""))))
			row.add_child(remove)
		_content.add_child(row)
	var leave := _button("Leave club")
	leave.pressed.connect(_on_leave)
	_content.add_child(leave)


static func _may_remove(actor: String, target: String) -> bool:
	if actor == "owner":
		return target != "owner"
	return actor == "admin" and target == "member"


func _build_start() -> void:
	_content.add_child(_heading("Start a club"))
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 8)
	_adjective = _picker(ClubsApi.ADJECTIVES)
	_noun = _picker(ClubsApi.NOUNS)
	names.add_child(_adjective)
	names.add_child(_noun)
	_content.add_child(names)
	var crests := HFlowContainer.new()
	crests.add_theme_constant_override("h_separation", 8)
	crests.add_theme_constant_override("v_separation", 8)
	_crest_buttons.clear()
	for c in 6:
		var b := _button(Companies.short_name_of(c))
		b.toggle_mode = true
		b.button_pressed = c == _crest
		b.custom_minimum_size = Vector2(96, ROW_HEIGHT)
		b.add_theme_color_override("font_color", Companies.color_of(c).darkened(0.35))
		b.pressed.connect(_on_crest.bind(c))
		_crest_buttons.append(b)
		crests.add_child(b)
	_content.add_child(crests)
	var create := _button("Start club")
	create.pressed.connect(_on_create)
	_content.add_child(create)


func _build_join(clubs: Array) -> void:
	_content.add_child(_heading("Join a club"))
	if clubs.is_empty():
		_content.add_child(_label("No open clubs right now. Start one!", 17))
	for c in clubs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		var name_label := _label("%s  %d/%d" % [String(c.get("name", "")), int(c.get("count", 0)), int(c.get("max", 30))], 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var join := _button("Join")
		join.custom_minimum_size = Vector2(96, ROW_HEIGHT)
		join.pressed.connect(_on_join.bind(String(c.get("id", ""))))
		row.add_child(join)
		_content.add_child(row)


func _build_league(league: Array, mine: String) -> void:
	_content.add_child(_heading("This week's league"))
	if league.is_empty():
		_content.add_child(_label("No club has points yet this week. Games with other people earn points for your club.", 17))
		return
	for r in league:
		var l := _label("%d. %s  %d" % [int(r.get("rank", 0)), String(r.get("name", "")), int(r.get("score", 0))], 18)
		if String(r.get("id", "")) == mine:
			l.add_theme_color_override("font_color", Companies.CHEST.darkened(0.3))
		_content.add_child(l)


func _on_crest(c: int) -> void:
	_crest = c
	for i in _crest_buttons.size():
		_crest_buttons[i].button_pressed = i == c


func _on_create() -> void:
	var res := await ClubsApi.create(_adjective.selected, _noun.selected, _crest)
	if res.is_empty():
		_status.text = ClubsApi.last_error
		return
	await refresh()


func _on_join(club_id: String) -> void:
	if (await ClubsApi.join(club_id)).is_empty():
		_status.text = ClubsApi.last_error
		return
	await refresh()


func _on_leave() -> void:
	if not await ClubsApi.leave():
		_status.text = ClubsApi.last_error
		return
	await refresh()


func _on_remove(user_id: String) -> void:
	if not await ClubsApi.kick(user_id):
		_status.text = ClubsApi.last_error
		return
	await refresh()


func _picker(words: Array[String]) -> OptionButton:
	var o := OptionButton.new()
	for w in words:
		o.add_item(w)
	o.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 18)
	return o


func _heading(text: String) -> Label:
	var l := _label(text, 22)
	l.add_theme_font_override("font", UiTheme.display_font())
	return l


func _label(text: String, px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Companies.INK)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	return b
