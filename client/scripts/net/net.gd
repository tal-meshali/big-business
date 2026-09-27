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


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		host = cfg.get_value("server", "host", host)
		port = cfg.get_value("server", "port", port)
		scheme = cfg.get_value("server", "scheme", scheme)
		display_name = cfg.get_value("player", "name", "")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "host", host)
	cfg.set_value("server", "port", port)
	cfg.set_value("server", "scheme", scheme)
	cfg.set_value("player", "name", display_name)
	cfg.save(SETTINGS_PATH)


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
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "quick_play", "{}")
	if rpc.is_exception():
		server_error.emit("quick play failed: %s" % rpc.get_exception().message)
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	return await _join_match(String(data.get("matchId", "")))


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
	if socket != null and not match_id.is_empty():
		await socket.leave_match_async(match_id)
	match_id = ""
	match_left.emit()


func send_ready() -> void:
	if match_id.is_empty():
		return
	socket.send_match_state_async(match_id, Protocol.OP_READY, "{}")


func send_action(action: Dictionary) -> void:
	if match_id.is_empty():
		return
	socket.send_match_state_async(match_id, Protocol.OP_ACTION, JSON.stringify(action))


func _on_match_state(state: NakamaRTAPI.MatchData) -> void:
	var data = JSON.parse_string(state.data)
	if data == null:
		return
	match state.op_code:
		Protocol.OP_VIEW:
			view_updated.emit(data)
		Protocol.OP_EVENTS:
			events_received.emit(int(data.get("seq", 0)), data.get("events", []))
		Protocol.OP_LOBBY:
			lobby_updated.emit(data)
		Protocol.OP_ERROR:
			server_error.emit(String(data.get("message", "error")))


func _on_match_presence(_event: NakamaRTAPI.MatchPresenceEvent) -> void:
	pass


func _on_socket_closed() -> void:
	match_id = ""
	connection_failed.emit("disconnected")
