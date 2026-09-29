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
signal player_forfeited(seat: int)
signal reconnecting(attempt: int)
signal reconnected

const SETTINGS_PATH := "user://net.cfg"
const DEFAULT_PORT := 7350
## Nakama friend state 3 is "blocked by me".
const FRIEND_STATE_BLOCKED := 3

var host: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var scheme: String = "http"
var server_key: String = "defaultkey"

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var match_id: String = ""
## The latest view of the current match ({} outside a game).
## WHY: the lobby changes scene on the first view, so the table would
## otherwise miss it and sit empty until the first move, or until the
## timer ran out when you move first.
var last_view: Dictionary = {}
var user_id: String = ""
var display_name: String = ""
## True while the current match is the tutorial (coach overlay on).
var tutorial_mode: bool = false
## Players muted locally (user id -> true), saved in SETTINGS_PATH.
var muted: Dictionary = {}
## Players this account has blocked (user id -> true), loaded from the
## server's friends list on connect so blocks survive reinstalls too.
var blocked: Dictionary = {}
var _reconnect_attempts: int = 0
var _closing: bool = false
var _reconnecting: bool = false


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		host = cfg.get_value("server", "host", host)
		port = cfg.get_value("server", "port", port)
		scheme = cfg.get_value("server", "scheme", scheme)
		display_name = cfg.get_value("player", "name", "")
		for id in cfg.get_value("social", "muted", PackedStringArray()):
			muted[String(id)] = true


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "host", host)
	cfg.set_value("server", "port", port)
	cfg.set_value("server", "scheme", scheme)
	cfg.set_value("player", "name", display_name)
	cfg.set_value("social", "muted", PackedStringArray(muted.keys()))
	cfg.save(SETTINGS_PATH)


## Parses what the player typed in the lobby's server field:
## "127.0.0.1" or "host:7350" (plain http, port 7350 unless given), or a
## URL such as "https://play.example.com" (port 443 unless given), which is
## how the TLS deployment in docs/deploy.md is reached.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	var out := {"scheme": "http", "host": "127.0.0.1", "port": DEFAULT_PORT}
	var sep := t.find("://")
	if sep >= 0:
		out["scheme"] = "https" if t.substr(0, sep).to_lower() == "https" else "http"
		out["port"] = 443 if out["scheme"] == "https" else 80
		t = t.substr(sep + 3)
	var slash := t.find("/")
	if slash >= 0:
		t = t.substr(0, slash)
	var colon := t.rfind(":")
	if colon > 0 and t.substr(colon + 1).is_valid_int():
		out["port"] = int(t.substr(colon + 1))
		t = t.substr(0, colon)
	if not t.is_empty():
		out["host"] = t
	return out


func set_server_address(text: String) -> void:
	var a := parse_address(text)
	scheme = a["scheme"]
	host = a["host"]
	port = a["port"]


## The server as the lobby field shows it: a bare host for the local
## default, a URL otherwise.
func server_address() -> String:
	if scheme == "http" and port == DEFAULT_PORT:
		return host
	var default_port := 443 if scheme == "https" else 80
	return "%s://%s%s" % [scheme, host, "" if port == default_port else ":%d" % port]


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
	socket.closed.connect(_on_socket_closed.bind(socket))
	_reconnect_attempts = 0
	await _load_blocked()
	connected.emit()
	return true


func _load_blocked() -> void:
	var res = await client.list_friends_async(session, FRIEND_STATE_BLOCKED, 1000)
	if res == null or res.is_exception():
		return
	blocked.clear()
	for f in res.friends:
		blocked[f.user.id] = true


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
	last_view = {}
	return true


func leave_match() -> void:
	if socket != null and not match_id.is_empty():
		await socket.leave_match_async(match_id)
	match_id = ""
	last_view = {}
	tutorial_mode = false
	match_left.emit()


## Give up the current game, then leave it. A bot plays the seat to the end.
func forfeit() -> void:
	if socket != null and not match_id.is_empty():
		await socket.send_match_state_async(match_id, Protocol.OP_FORFEIT, "{}")
	await leave_match()


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


## Progression: {progress: {...}, dailyAvailable: bool}, or {} on failure.
func get_profile() -> Dictionary:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "get_profile", "{}")
	if rpc.is_exception():
		return {}
	return JSON.parse_string(rpc.payload)


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


## Blocks a player server-side (they can no longer friend or message you)
## and hides their emotes from now on.
func block_player(target_user_id: String) -> bool:
	blocked[target_user_id] = true
	var res: NakamaAsyncResult = await client.block_friends_async(session, [target_user_id])
	return not res.is_exception()


func mute_player(target_user_id: String, on: bool = true) -> void:
	if on:
		muted[target_user_id] = true
	else:
		muted.erase(target_user_id)
	save_settings()


func is_blocked(target_user_id: String) -> bool:
	return blocked.has(target_user_id)


## True when this player's emotes should be hidden (muted or blocked).
func is_muted(target_user_id: String) -> bool:
	return muted.has(target_user_id) or blocked.has(target_user_id)


func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	var data = JSON.parse_string(state.data)
	if data == null:
		return
	match state.op_code:
		Protocol.OP_VIEW:
			last_view = data
			view_updated.emit(data)
		Protocol.OP_EVENTS:
			events_received.emit(int(data.get("seq", 0)), data.get("events", []))
		Protocol.OP_LOBBY:
			lobby_updated.emit(data)
		Protocol.OP_ERROR:
			server_error.emit(String(data.get("message", "error")))
		Protocol.OP_EMOTE_SHOWN:
			emote_shown.emit(int(data.get("seat", -1)), String(data.get("emote", "")))
		Protocol.OP_FORFEITED:
			player_forfeited.emit(int(data.get("seat", -1)))


func _on_match_presence(_event: NakamaRTAPI.MatchPresenceEvent) -> void:
	pass


func _on_socket_closed(closed_socket: NakamaSocket) -> void:
	# A socket replaced by an earlier reconnect may still report its close.
	if _closing or closed_socket != socket:
		return
	_try_reconnect()


## WHY: a phone that sleeps with the app in the background may come back
## with a socket the server already dropped, and the close is not always
## reported until the next send. Check on resume and rejoin straight away.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		check_connection()


## Reconnects (and rejoins the match) if we had a session but the socket is gone.
func check_connection() -> void:
	if _closing or _reconnecting or session == null or socket == null:
		return
	if not socket.is_connected_to_host():
		_try_reconnect()


## Reconnect with backoff and rejoin the match we were in; the server keeps
## the seat and sends a fresh view on rejoin.
func _try_reconnect() -> void:
	if _reconnecting:
		return
	_reconnecting = true
	var previous_match := match_id
	var previous_tutorial := tutorial_mode
	for attempt in range(1, 6):
		_reconnect_attempts = attempt
		reconnecting.emit(attempt)
		await get_tree().create_timer(minf(1.0 * attempt, 5.0)).timeout
		if await connect_to_server():
			_reconnecting = false
			if not previous_match.is_empty():
				tutorial_mode = previous_tutorial
				if await _join_match(previous_match):
					reconnected.emit()
					return
			match_id = ""
			reconnected.emit()
			return
	_reconnecting = false
	match_id = ""
	connection_failed.emit("disconnected")
