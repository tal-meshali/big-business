class_name FriendsPanel
extends PanelContainer
## Lobby friends panel: friends with an online dot, add by name, remove,
## invite to the current private room, incoming invites with a Join
## button, a daily gift of track points to each friend (and collecting
## theirs), and Watch for a friend who is in a game. Self-contained: it talks to Net itself. main.gd only sets
## `room_code` and handles `join_requested`.

signal join_requested(code: String)
## Gifts turned into track points: the lobby reloads the profile.
signal gifts_collected
## Joined a friend's game as a watcher; the table opens with the first view.
signal watch_started

const ONLINE := Color("#3F9E4F")
const OFFLINE := Color("#BDBDBD")
## Minimum touch target on a phone.
const TOUCH := 48
## Nakama friend states.
const STATE_FRIENDS := 0
const STATE_REQUEST_SENT := 1
const STATE_REQUEST_RECEIVED := 2

## Code of the private room the lobby is in ("" outside one). Invite
## buttons show only while it is set.
var room_code: String = "":
	set(value):
		room_code = value
		_render_friends()

var _friends: Array = []
## From gift_state / friends_playing; refreshed with the list.
var _gifts: Dictionary = {}
var _playing: Array = []
var _gift_row: HBoxContainer
var _gift_label: Label
var _collect_button: Button
var _list: VBoxContainer
var _invites: VBoxContainer
var _name_edit: LineEdit
var _add_button: Button
var _status: Label


func _ready() -> void:
	_build()
	Net.invite_received.connect(show_invite)
	visibility_changed.connect(_on_visibility_changed)
	for inv in Net.take_pending_invites():
		show_invite(String(inv.get("fromName", "A friend")), String(inv.get("code", "")))


func _build() -> void:
	# The deed panel supplies the look; this container only positions it.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.deed_panel(Companies.CHANCE, "Friends", Companies.INK)
	deed["title"].add_theme_font_size_override("font_size", 24)
	add_child(deed["panel"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	deed["body"].add_child(box)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	box.add_child(add_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "friend's player name"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, TOUCH)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_add_pressed())
	add_row.add_child(_name_edit)
	_add_button = Button.new()
	_add_button.text = "Add"
	_add_button.custom_minimum_size = Vector2(96, TOUCH)
	_add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(_add_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Companies.INK_SOFT)
	box.add_child(_status)

	_gift_row = HBoxContainer.new()
	_gift_row.add_theme_constant_override("separation", 8)
	_gift_row.visible = false
	box.add_child(_gift_row)
	_gift_label = Label.new()
	_gift_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gift_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gift_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gift_label.add_theme_font_size_override("font_size", 18)
	_gift_row.add_child(_gift_label)
	_collect_button = Button.new()
	_collect_button.text = "Collect"
	_collect_button.custom_minimum_size = Vector2(110, TOUCH)
	_collect_button.pressed.connect(_on_collect_pressed)
	_gift_row.add_child(_collect_button)

	_invites = VBoxContainer.new()
	_invites.add_theme_constant_override("separation", 8)
	box.add_child(_invites)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	_render_friends()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()


## Reloads the friends list from the server (no-op while offline).
func refresh() -> void:
	if not Net.is_connected_to_server():
		_status.text = "Connect to see your friends."
		return
	set_friends(await Net.list_friends())
	set_extras(await SocialApi.gift_state(), await SocialApi.friends_playing())


## Gift and watch state for the rows: gift_state and friends_playing.
func set_extras(gifts: Dictionary, playing: Array) -> void:
	_gifts = gifts
	_playing = playing
	var waiting := int(gifts.get("waiting", 0))
	if _gift_row != null:
		_gift_row.visible = waiting > 0
		var names: Array = gifts.get("names", [])
		var from := ", ".join(PackedStringArray(names)) if not names.is_empty() else "friends"
		_gift_label.text = "%d %s from %s (+%d track points each)" % [waiting, "gift" if waiting == 1 else "gifts", from, int(gifts.get("points", 0))]
		_collect_button.disabled = int(gifts.get("claimLeft", 0)) <= 0
		if _collect_button.disabled:
			_gift_label.text += ". Collect more tomorrow."
	_render_friends()


## Renders friend rows ({userId, name, online, state}); used by refresh()
## and by the smoke test.
func set_friends(rows: Array) -> void:
	_friends = rows
	_render_friends()


func _render_friends() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.free()
	if _friends.is_empty():
		var empty := Label.new()
		empty.text = "No friends yet. Add one by their player name."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return
	for f in _friends:
		_list.add_child(_friend_row(f))


## Row layout: dot, name, state button (Invite / Accept / Pending), Remove.
func _friend_row(f: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, TOUCH)
	var user_id := String(f.get("userId", ""))
	var state := int(f.get("state", STATE_FRIENDS))

	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 20)
	dot.add_theme_color_override("font_color", ONLINE if bool(f.get("online", false)) else OFFLINE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var name_label := Label.new()
	name_label.text = String(f.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	var action := Button.new()
	action.custom_minimum_size = Vector2(96, TOUCH)
	match state:
		STATE_REQUEST_SENT:
			action.text = "Pending"
			action.disabled = true
		STATE_REQUEST_RECEIVED:
			action.text = "Accept"
			action.pressed.connect(_on_accept_pressed.bind(user_id, action))
		_:
			action.text = "Invite"
			# WHY: an invite needs a room to point at; public lobbies have no code.
			action.visible = not room_code.is_empty()
			action.pressed.connect(_on_invite_pressed.bind(user_id, action))
	row.add_child(action)

	if state == STATE_FRIENDS:
		if _playing.has(user_id):
			var watch := Button.new()
			watch.text = "Watch"
			watch.custom_minimum_size = Vector2(96, TOUCH)
			watch.pressed.connect(_on_watch_pressed.bind(user_id, watch))
			row.add_child(watch)
		var gift := Button.new()
		var sent: bool = Array(_gifts.get("sentToday", [])).has(user_id)
		gift.text = "Sent" if sent else "Gift"
		gift.disabled = sent or int(_gifts.get("sendLeft", 1)) <= 0
		gift.custom_minimum_size = Vector2(96, TOUCH)
		gift.pressed.connect(_on_gift_pressed.bind(user_id, gift))
		row.add_child(gift)

	var remove := Button.new()
	remove.text = "Remove"
	remove.custom_minimum_size = Vector2(96, TOUCH)
	remove.pressed.connect(_on_remove_pressed.bind(user_id, remove))
	row.add_child(remove)
	return row


## Shows "X invited you to room CODE" with Join and dismiss buttons.
func show_invite(from_name: String, code: String) -> void:
	if code.is_empty() or _invites == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var text := Label.new()
	text.text = "%s invited you to room %s" % [from_name, code]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(96, TOUCH)
	join.pressed.connect(func() -> void:
		_drop_invite(row)
		join_requested.emit(code))
	row.add_child(join)
	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.custom_minimum_size = Vector2(TOUCH, TOUCH)
	dismiss.pressed.connect(func() -> void: _drop_invite(row))
	row.add_child(dismiss)
	_invites.add_child(row)
	visible = true


func _drop_invite(row: Control) -> void:
	if row.get_parent() == _invites:
		_invites.remove_child(row)
	row.queue_free()


func _on_add_pressed() -> void:
	var username := _name_edit.text.strip_edges()
	if username.is_empty():
		return
	_add_button.disabled = true
	_status.text = "Adding %s..." % username
	var ok: bool = await Net.add_friend_by_name(username)
	_add_button.disabled = false
	if ok:
		_name_edit.text = ""
		_status.text = "Request sent to %s. You're friends once they add you back." % username
		refresh()
	else:
		_status.text = "No player named %s." % username


func _on_accept_pressed(user_id: String, button: Button) -> void:
	button.disabled = true
	var ok: bool = await Net.add_friend(user_id)
	if ok:
		refresh()
	elif is_instance_valid(button):
		button.disabled = false


func _on_remove_pressed(user_id: String, button: Button) -> void:
	button.disabled = true
	var ok: bool = await Net.remove_friend(user_id)
	if ok:
		refresh()
	elif is_instance_valid(button):
		button.disabled = false


func _on_invite_pressed(user_id: String, button: Button) -> void:
	button.disabled = true
	var ok: bool = await Net.invite_friend(user_id, room_code)
	# The list may have been re-rendered while the request was in flight.
	if not is_instance_valid(button):
		return
	button.text = "Sent" if ok else "Invite"
	button.disabled = ok


func _on_gift_pressed(user_id: String, button: Button) -> void:
	button.disabled = true
	var ok: bool = await SocialApi.send_gift(user_id)
	if ok:
		_status.text = "Gift sent. They get %d track points." % int(_gifts.get("points", 5))
		set_extras(await SocialApi.gift_state(), _playing)
	else:
		_status.text = SocialApi.last_error
		if is_instance_valid(button):
			button.disabled = false


func _on_collect_pressed() -> void:
	_collect_button.disabled = true
	var res: Dictionary = await SocialApi.claim_gifts()
	if res.is_empty():
		_status.text = SocialApi.last_error
	else:
		_status.text = "Collected %d track points from friends." % int(res.get("points", 0))
		gifts_collected.emit()
	set_extras(await SocialApi.gift_state(), _playing)


func _on_watch_pressed(user_id: String, button: Button) -> void:
	button.disabled = true
	if not await Net.watch_friend(user_id):
		_status.text = "That game can't be watched right now."
		if is_instance_valid(button):
			button.disabled = false
		return
	watch_started.emit()
