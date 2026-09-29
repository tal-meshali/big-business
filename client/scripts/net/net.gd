extends Node
## Autoload "Net": owns the Nakama client, session and socket, and turns
## match messages into typed signals. Everything game-related goes through
## here so scenes never touch the Nakama API directly.

signal connected
signal connection_failed(reason: String)
signal lobby_updated(lobby: Dictionary)
signal view_updated(view: Dictionary)
signal events_received(seq: int, events: Array)
signal server_error(message: String)
signal match_left
signal emote_shown(seat: int, emote: String)
signal reconnecting(attempt: int)
signal reconnected
## A friend invited us to a private room, live over the socket or found as a
## persistent notification on connect. Also queued in `pending_invites`.
signal invite_received(from_name: String, code: String)

const SETTINGS_PATH := "user://net.cfg"

var host: String = "127.0.0.1"
var port: int = 7350
var scheme: String = "http"
var server_key: String = "defaultkey"

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var match_id: String = ""
var user_id: String = ""
var display_name: String = ""
## True while the current match is the tutorial (coach overlay on).
var tutorial_mode: bool = false
## True once the player has finished (or skipped) the tutorial; persisted so
## the first "Play now" routes new players into it only once.
var tutorial_done: bool = false
## Players muted locally (user id -> true), persisted in user://net.cfg.
## WHY: block is server-side via the friends API, but mute is local only, so
## it must survive restarts or a muted player's emotes come back on relaunch.
var muted: Dictionary = {}
var _reconnect_attempts: int = 0
var _closing: bool = false


func _ready() -> void:
	_load_settings()
	connected.connect(_on_connected_social)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		host = cfg.get_value("server", "host", host)
		port = cfg.get_value("server", "port", port)
		scheme = cfg.get_value("server", "scheme", scheme)
		display_name = cfg.get_value("player", "name", "")
		tutorial_done = bool(cfg.get_value("player", "tutorial_done", false))
		var saved_muted = cfg.get_value("social", "muted", {})
		muted = saved_muted if saved_muted is Dictionary else {}


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "host", host)
	cfg.set_value("server", "port", port)
	cfg.set_value("server", "scheme", scheme)
	cfg.set_value("player", "name", display_name)
	cfg.set_value("player", "tutorial_done", tutorial_done)
	cfg.set_value("social", "muted", muted)
	cfg.save(SETTINGS_PATH)


## Parse what a player types into the host field into {scheme, host, port}.
## Accepts "play.example.com", "play.example.com:7350", "https://play.example.com",
## "http://127.0.0.1:7350" and "https://play.example.com/" (a trailing path is
## ignored). Without a scheme in the text, `default_scheme` applies; the port
## defaults to 7350 for http and 443 for https (Caddy terminates TLS, see
## docs/deploy.md).
static func parse_host_input(text: String, default_scheme: String = "http") -> Dictionary:
	var rest := text.strip_edges()
	var out_scheme := default_scheme
	var lower := rest.to_lower()
	if lower.begins_with("https://"):
		out_scheme = "https"
		rest = rest.substr(8)
	elif lower.begins_with("http://"):
		out_scheme = "http"
		rest = rest.substr(7)
	var slash := rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	var out_host := rest
	var out_port := 443 if out_scheme == "https" else 7350
	var colon := rest.rfind(":")
	if colon >= 0 and rest.substr(colon + 1).is_valid_int():
		out_host = rest.substr(0, colon)
		out_port = int(rest.substr(colon + 1))
	return {"scheme": out_scheme, "host": out_host, "port": out_port}


## Remember that the tutorial was finished or skipped, so "Play now" goes
## straight to a real game from now on.
func mark_tutorial_done() -> void:
	if tutorial_done:
		return
	tutorial_done = true
	save_settings()


func is_connected_to_server() -> bool:
	return socket != null and socket.is_connected_to_host()


## Authenticate with a persistent device id and open the realtime socket.
func connect_to_server() -> bool:
	client = Nakama.create_client(server_key, host, port, scheme, Nakama.DEFAULT_TIMEOUT, NakamaLogger.LOG_LEVEL.WARNING)
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		device_id = _persistent_device_id()
	var username := display_name if not display_name.is_empty() else ""
	session = await client.authenticate_device_async(device_id, username if not username.is_empty() else null, true)
	if session.is_exception():
		var msg := "auth failed: %s" % session.get_exception().message
		push_warning(msg)
		connection_failed.emit(msg)
		return false
	user_id = session.user_id
	if display_name.is_empty():
		display_name = session.username

	socket = Nakama.create_socket_from(client)
	var connected_result: NakamaAsyncResult = await socket.connect_async(session)
	if connected_result.is_exception():
		var msg := "socket failed: %s" % connected_result.get_exception().message
		push_warning(msg)
		connection_failed.emit(msg)
		return false
	socket.received_match_state.connect(_on_match_state)
	socket.received_match_presence.connect(_on_match_presence)
	socket.closed.connect(_on_socket_closed)
	_reconnect_attempts = 0
	connected.emit()
	return true


func _persistent_device_id() -> String:
	var path := "user://device_id"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	var id := "%s-%d" % [str(randi()).sha256_text().substr(0, 16), Time.get_unix_time_from_system()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(id)
	return id


## Ask the server for an open public game (or a new one) and join it.
func quick_play() -> bool:
	tutorial_mode = false
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "quick_play", "{}")
	if rpc.is_exception():
		server_error.emit("quick play failed: %s" % rpc.get_exception().message)
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	return await _join_match(String(data.get("matchId", "")))


## Start a solo tutorial game against two slow bots with no timer.
func start_tutorial() -> bool:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "quick_play", JSON.stringify({"tutorial": true}))
	if rpc.is_exception():
		server_error.emit("tutorial failed: %s" % rpc.get_exception().message)
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	tutorial_mode = true
	var ok := await _join_match(String(data.get("matchId", "")))
	if not ok:
		tutorial_mode = false
	return ok


## Create a private room. Returns the room code, or "" on failure.
func create_room(step_seconds: int = 30, max_seats: int = 7) -> String:
	var payload := JSON.stringify({"stepSeconds": step_seconds, "maxSeats": max_seats})
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "create_room", payload)
	if rpc.is_exception():
		server_error.emit("create room failed: %s" % rpc.get_exception().message)
		return ""
	var data: Dictionary = JSON.parse_string(rpc.payload)
	if not await _join_match(String(data.get("matchId", ""))):
		return ""
	return String(data.get("code", ""))


## Join a private room by its 6-character code.
func join_room(code: String) -> bool:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "join_room", JSON.stringify({"code": code.to_upper().strip_edges()}))
	if rpc.is_exception():
		server_error.emit("room not found")
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	return await _join_match(String(data.get("matchId", "")))


func _join_match(id: String) -> bool:
	if id.is_empty():
		server_error.emit("no match id")
		return false
	var joined: NakamaRTAPI.Match = await socket.join_match_async(id)
	if joined.is_exception():
		server_error.emit("join failed: %s" % joined.get_exception().message)
		return false
	match_id = id
	return true


func leave_match() -> void:
	# Leaving the tutorial early counts as done: skipping is a choice.
	if tutorial_mode:
		mark_tutorial_done()
	if socket != null and not match_id.is_empty():
		await socket.leave_match_async(match_id)
	match_id = ""
	tutorial_mode = false
	match_left.emit()


func send_ready() -> void:
	if match_id.is_empty():
		return
	socket.send_match_state_async(match_id, Protocol.OP_READY, "{}")


func send_action(action: Dictionary) -> void:
	if match_id.is_empty():
		return
	socket.send_match_state_async(match_id, Protocol.OP_ACTION, JSON.stringify(action))


func send_emote(emote_id: String) -> void:
	if match_id.is_empty():
		return
	socket.send_match_state_async(match_id, Protocol.OP_EMOTE, JSON.stringify({"emote": emote_id}))


## Progression: {progress: {...}, dailyAvailable: bool, quests, trackPoints,
## unlocked, equipped, track}, or {} on failure. Applies the equipped cosmetics.
func get_profile() -> Dictionary:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "get_profile", "{}")
	if rpc.is_exception():
		return {}
	var data: Dictionary = JSON.parse_string(rpc.payload)
	Cosmetics.apply_equipped(data.get("equipped", {}))
	return data


## Daily bonus: {claimed: bool, xpAwarded: int, progress: {...}}, or {} on failure.
func claim_daily() -> Dictionary:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "claim_daily", "{}")
	if rpc.is_exception():
		return {}
	return JSON.parse_string(rpc.payload)


## Top season records plus the caller's own. Returns [] on failure.
func season_leaderboard(limit: int = 20) -> Array:
	var res: NakamaAPI.ApiLeaderboardRecordList = await client.list_leaderboard_records_async(session, "season", [user_id], null, limit)
	if res.is_exception():
		return []
	var rows: Array = []
	for r in res.records:
		rows.append({"userId": r.owner_id, "name": r.username, "score": int(r.score), "rank": int(r.rank), "wins": int(r.subscore)})
	for r in res.owner_records:
		rows.append({"userId": r.owner_id, "name": r.username, "score": int(r.score), "rank": int(r.rank), "wins": int(r.subscore), "mine": true})
	return rows


## Files a report into the server's moderation queue.
func report_player(target_user_id: String, reason: String, note: String = "") -> bool:
	var payload := JSON.stringify({"userId": target_user_id, "reason": reason, "matchId": match_id, "note": note})
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "report_player", payload)
	return not rpc.is_exception()


## Blocks a player server-side (they can no longer friend or message you) and mutes them locally.
func block_player(target_user_id: String) -> bool:
	muted[target_user_id] = true
	save_settings()
	var res: NakamaAsyncResult = await client.block_friends_async(session, [target_user_id])
	return not res.is_exception()


func mute_player(target_user_id: String, on: bool = true) -> void:
	if on:
		muted[target_user_id] = true
	else:
		muted.erase(target_user_id)
	save_settings()


func is_muted(target_user_id: String) -> bool:
	return muted.has(target_user_id)


func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	var data = JSON.parse_string(state.data)
	if data == null:
		return
	match state.op_code:
		Protocol.OP_VIEW:
			if tutorial_mode and String(data.get("phase", "")) == "ended":
				mark_tutorial_done()
			view_updated.emit(data)
		Protocol.OP_EVENTS:
			events_received.emit(int(data.get("seq", 0)), data.get("events", []))
		Protocol.OP_LOBBY:
			lobby_updated.emit(data)
		Protocol.OP_ERROR:
			server_error.emit(String(data.get("message", "error")))
		Protocol.OP_EMOTE_SHOWN:
			emote_shown.emit(int(data.get("seat", -1)), String(data.get("emote", "")))


func _on_match_presence(_event: NakamaRTAPI.MatchPresenceEvent) -> void:
	pass


func _on_socket_closed() -> void:
	if _closing:
		return
	_try_reconnect()


## Reconnect with backoff and rejoin the match we were in; the server keeps
## the seat and sends a fresh view on rejoin.
func _try_reconnect() -> void:
	var previous_match := match_id
	var previous_tutorial := tutorial_mode
	for attempt in range(1, 6):
		_reconnect_attempts = attempt
		reconnecting.emit(attempt)
		await get_tree().create_timer(minf(1.0 * attempt, 5.0)).timeout
		if await connect_to_server():
			if not previous_match.is_empty():
				tutorial_mode = previous_tutorial
				if await _join_match(previous_match):
					reconnected.emit()
					return
			match_id = ""
			reconnected.emit()
			return
	match_id = ""
	connection_failed.emit("disconnected")


# --- Friends and invites ------------------------------------------------------

## Invites not yet shown by a friends panel ({fromName, code}), so one that
## arrives during a game is still offered back in the lobby.
var pending_invites: Array = []
## Notification ids already surfaced this session, so a persistent invite is
## shown once even across reconnects.
var _seen_invites: Dictionary = {}


## Friends in every state except blocked: [{userId, name, online, state}] with
## Nakama's states (0 friends, 1 request sent, 2 request received).
func list_friends() -> Array:
	var rows: Array = []
	if client == null or session == null:
		return rows
	var res = await client.list_friends_async(session, null, 100)
	if res.is_exception():
		return rows
	for f in res.friends:
		if f.user == null or f.state == 3:
			continue
		var shown_name: String = f.user.display_name if not f.user.display_name.is_empty() else f.user.username
		rows.append({"userId": f.user.id, "name": shown_name, "online": f.user.online, "state": int(f.state)})
	return rows


## Sends a friend request to a player by exact username (adding back accepts
## theirs). False when no such player exists.
func add_friend_by_name(username: String) -> bool:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "find_player", JSON.stringify({"name": username.strip_edges()}))
	if rpc.is_exception():
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	return await add_friend(String(data.get("userId", "")))


## Sends a friend request by user id, or accepts a received one.
func add_friend(target_user_id: String) -> bool:
	if target_user_id.is_empty():
		return false
	var res: NakamaAsyncResult = await client.add_friends_async(session, [target_user_id])
	return not res.is_exception()


## Removes a friend (or cancels a pending request) both ways.
func remove_friend(target_user_id: String) -> bool:
	var res: NakamaAsyncResult = await client.delete_friends_async(session, PackedStringArray([target_user_id]))
	return not res.is_exception()


## Invites a mutual friend to the private room `code`; the server refuses
## strangers, pending requests and players who blocked us.
func invite_friend(target_user_id: String, code: String) -> bool:
	var payload := JSON.stringify({"userId": target_user_id, "code": code})
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "invite_friend", payload)
	if rpc.is_exception():
		server_error.emit("invite failed: %s" % rpc.get_exception().message)
		return false
	return true


## Hands over (and clears) invites that arrived while no panel was listening.
func take_pending_invites() -> Array:
	var out := pending_invites
	pending_invites = []
	return out


func _on_connected_social() -> void:
	socket.received_notification.connect(_on_notification)
	_fetch_pending_invites()


func _on_notification(n: NakamaAPI.ApiNotification) -> void:
	if n.code != Protocol.INVITE_CODE or _seen_invites.has(n.id):
		return
	_seen_invites[n.id] = true
	var content = JSON.parse_string(n.content)
	if not content is Dictionary:
		return
	var from_name := String(content.get("fromName", "A friend"))
	var code := String(content.get("code", ""))
	if code.is_empty():
		return
	# WHY: a listening panel shows it now; otherwise it waits in the queue for
	# the next lobby visit. Never both, or the invite comes back a second time.
	if invite_received.get_connections().is_empty():
		pending_invites.append({"fromName": from_name, "code": code})
	else:
		invite_received.emit(from_name, code)


## Invites sent while we were offline are persistent notifications. Surface
## them once, then delete them server-side.
## WHY: rooms live minutes, so an invite shown once is either used now or
## stale; deleting keeps old codes from reappearing at every launch.
func _fetch_pending_invites() -> void:
	var res = await client.list_notifications_async(session, 20)
	if res.is_exception():
		return
	var ids := PackedStringArray()
	for n in res.notifications:
		if n.code == Protocol.INVITE_CODE:
			ids.append(n.id)
			_on_notification(n)
	if not ids.is_empty():
		await client.delete_notifications_async(session, ids)


## Claims a completed quest: {ok, trackPoints, unlocked}, or {} on failure.
func claim_quest(id: String) -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "claim_quest", JSON.stringify({"id": id}))
	if rpc.is_exception():
		return {}
	return JSON.parse_string(rpc.payload)


## Equips an unlocked cosmetic ("cardBack" or "table"): {ok, equipped}, or {} on failure.
func equip_cosmetic(slot: String, id: String) -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "equip_cosmetic", JSON.stringify({"slot": slot, "id": id}))
	if rpc.is_exception():
		return {}
	var data: Dictionary = JSON.parse_string(rpc.payload)
	if data.get("ok", false):
		Cosmetics.apply_equipped(data.get("equipped", {}))
	return data
