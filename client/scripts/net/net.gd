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
## A friend invited us to a private room, live over the socket or found as a
## persistent notification on connect. Also queued in `pending_invites`.
signal invite_received(from_name: String, code: String)
## Linking a provider found it already belongs to another account (a
## reinstall), so we signed in to that account instead.
signal account_switched(provider_name: String)
## The server's Remote Config arrived and `RemoteConfig` now reflects it.
signal remote_config_updated
## The room's custom deck (CardArt.room_deck) or its pictures changed; cards redraw.
signal custom_deck_changed

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
## Code of the private room we are in ("" otherwise); the server wants it
## with every join, including a rejoin after a reconnect.
var room_code: String = ""
## The latest view of the current match ({} outside a game).
## WHY: the lobby changes scene on the first view, so the table would
## otherwise miss it and sit empty until the first move, or until the
## timer ran out when you move first.
var last_view: Dictionary = {}
var user_id: String = ""
var display_name: String = ""
## True while the current match is the tutorial (coach overlay on).
var tutorial_mode: bool = false
## Sign-in provider used last ("apple", "google" or "" for the device id),
## persisted so the next launch tries it first when a token is available.
var provider: String = ""
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
	CardArt.load_settings()
	connected.connect(_on_connected_social)
	connected.connect(_on_connected_services)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		host = cfg.get_value("server", "host", host)
		port = cfg.get_value("server", "port", port)
		scheme = cfg.get_value("server", "scheme", scheme)
		display_name = cfg.get_value("player", "name", "")
		for id in cfg.get_value("social", "muted", PackedStringArray()):
			muted[String(id)] = true
		provider = String(cfg.get_value("player", "provider", ""))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "host", host)
	cfg.set_value("server", "port", port)
	cfg.set_value("server", "scheme", scheme)
	cfg.set_value("player", "name", display_name)
	cfg.set_value("player", "provider", provider)
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
## `connect_preferred` tries the remembered social provider first.
func connect_to_server() -> bool:
	_make_client()
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		device_id = _persistent_device_id()
	session = await client.authenticate_device_async(device_id, _create_username(), true)
	if session.is_exception():
		var msg := "auth failed: %s" % session.get_exception().message
		push_warning(msg)
		connection_failed.emit(msg)
		return false
	return await _open_socket()


## Creates the client for the current host settings.
func _make_client() -> void:
	client = Nakama.create_client(server_key, host, port, scheme, Nakama.DEFAULT_TIMEOUT, NakamaLogger.LOG_LEVEL.WARNING)


## The username to create a new account with, or null to let Nakama pick.
func _create_username():
	return display_name if not display_name.is_empty() else null


## Adopts `session` and opens the realtime socket on it. Shared by the
## device-id and social sign-ins so they behave identically after auth.
func _open_socket() -> bool:
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
	var code := String(data.get("code", ""))
	if not await _join_match(String(data.get("matchId", "")), code):
		return ""
	return code


## Join a private room by its 6-character code.
func join_room(code: String) -> bool:
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "join_room", JSON.stringify({"code": code.to_upper().strip_edges()}))
	if rpc.is_exception():
		server_error.emit("room not found")
		return false
	var data: Dictionary = JSON.parse_string(rpc.payload)
	return await _join_match(String(data.get("matchId", "")), String(data.get("code", "")))


## Joins a match. Private rooms need their code: the server refuses a join
## by match id alone, since match ids can be listed by any client.
func _join_match(id: String, code: String = "") -> bool:
	if id.is_empty():
		server_error.emit("no match id")
		return false
	var metadata = {"code": code} if not code.is_empty() else null
	var joined: NakamaRTAPI.Match = await socket.join_match_async(id, metadata)
	if joined.is_exception():
		server_error.emit("join failed: %s" % joined.get_exception().message)
		return false
	match_id = id
	room_code = code
	last_view = {}
	return true


func leave_match() -> void:
	if socket != null and not match_id.is_empty():
		await socket.leave_match_async(match_id)
	match_id = ""
	room_code = ""
	last_view = {}
	tutorial_mode = false
	_set_room_deck({})
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
	# Reporting the player whose custom deck is on the table reports its art too.
	if CardArt.deck_owner() == target_user_id:
		for h in CardArt.deck_hashes():
			await client.rpc_async(session, "report_card_art", JSON.stringify({"hash": h, "matchId": match_id}))
	return not rpc.is_exception()


## Blocks a player server-side (they can no longer friend or message you)
## and hides their emotes from now on.
func block_player(target_user_id: String) -> bool:
	blocked[target_user_id] = true
	if CardArt.deck_owner() == target_user_id:
		_set_room_deck({})
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
		Protocol.OP_DECK:
			if data is Dictionary and not is_blocked(String(data.get("owner", ""))):
				_set_room_deck(data)
				await fetch_card_art(CardArt.missing_hashes())
				custom_deck_changed.emit()


func _set_room_deck(deck: Dictionary) -> void:
	if deck.is_empty() and CardArt.room_deck.is_empty():
		return
	CardArt.set_room_deck(deck)
	custom_deck_changed.emit()


## Fetches pictures by hash into CardArt's cache. Returns how many arrived.
func fetch_card_art(hashes: Array[String]) -> int:
	if hashes.is_empty() or client == null or session == null:
		return 0
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "get_card_art", JSON.stringify({"hashes": hashes}))
	if rpc.is_exception():
		return 0
	var data = JSON.parse_string(rpc.payload)
	var got := 0
	if data is Dictionary and data.get("art") is Dictionary:
		for h in data["art"]:
			if CardArt.add_art(String(h), String(data["art"][h])):
				got += 1
	return got


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
	var previous_code := room_code
	var previous_tutorial := tutorial_mode
	for attempt in range(1, 6):
		_reconnect_attempts = attempt
		reconnecting.emit(attempt)
		await get_tree().create_timer(minf(1.0 * attempt, 5.0)).timeout
		if await _reconnect_session():
			_reconnecting = false
			if not previous_match.is_empty():
				tutorial_mode = previous_tutorial
				if await _join_match(previous_match, previous_code):
					reconnected.emit()
					return
			match_id = ""
			reconnected.emit()
			return
	_reconnecting = false
	match_id = ""
	connection_failed.emit("disconnected")


## Reopens the socket for the account we were signed in as.
## WHY: connect_to_server signs in with the device id, which after an Apple
## or Google sign-in is a different account; rejoining as that account would
## be refused and the seat would time out. The current session is reused
## while valid, otherwise the remembered sign-in runs again.
func _reconnect_session() -> bool:
	if session != null and not session.is_exception() and not session.would_expire_in(60):
		return await _open_socket()
	return await connect_preferred()


# --- Friends and invites ------------------------------------------------------

## Invites not yet shown by a friends panel ({fromName, code}), so one that
## arrives during a game is still offered back in the lobby.
var pending_invites: Array = []
## Notification ids already surfaced this session, so a persistent invite is
## shown once even across reconnects.
var _seen_invites: Dictionary = {}
## Pages of 100 notifications read at connect when looking for invites.
const NOTIFICATION_PAGES := 5


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
	socket.received_notification.connect(_on_live_notification)
	_fetch_pending_invites()


## An invite pushed over the socket is also stored as a persistent
## notification; once surfaced it is deleted so the next launch does not
## offer it again with a stale room code.
func _on_live_notification(n: NakamaAPI.ApiNotification) -> void:
	_on_notification(n)
	if n.code == Protocol.INVITE_CODE and client != null and session != null:
		await client.delete_notifications_async(session, PackedStringArray([n.id]))


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
## WHY paging: Nakama's own friend notifications are persistent too and are
## never deleted here, so a first page alone could be all friend notices.
func _fetch_pending_invites() -> void:
	var ids := PackedStringArray()
	var cursor = null
	for page in NOTIFICATION_PAGES:
		var res = await client.list_notifications_async(session, 100, cursor)
		if res.is_exception():
			break
		for n in res.notifications:
			if n.code == Protocol.INVITE_CODE:
				ids.append(n.id)
				_on_notification(n)
		if res.notifications.is_empty() or res.cacheable_cursor.is_empty() or res.cacheable_cursor == cursor:
			break
		cursor = res.cacheable_cursor
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


# --- Account linking (Sign in with Apple / Google) -----------------------------
# WHY: a device id is lost on reinstall. Linking a provider to the guest
# account keeps XP, cosmetics and friends; the token itself comes from
# SocialTokens (native plugins, a local step in docs/TODO-local.md E).

## Which sign-in methods the account has: {apple, google, device, username};
## {} when offline or on failure.
func get_account_links() -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "account_links", "{}")
	if rpc.is_exception():
		return {}
	var data = JSON.parse_string(rpc.payload)
	return data if data is Dictionary else {}


## Text for the lobby's account row from an `account_links` result (or {}
## before it arrives): "Guest account (device)" or the linked providers.
static func describe_account_links(links: Dictionary) -> String:
	var names := PackedStringArray()
	if links.get("apple", false):
		names.append("Apple")
	if links.get("google", false):
		names.append("Google")
	if names.is_empty():
		return "Guest account (device)"
	return "Signed in with %s" % " and ".join(names)


## Links an Apple identity token to the current account.
func link_apple(identity_token: String) -> bool:
	if identity_token.is_empty() or client == null or session == null:
		return false
	var res: NakamaAsyncResult = await client.link_apple_async(session, identity_token)
	if res.is_exception():
		# Already linked to another account (typically ours before a
		# reinstall): sign in to that one instead of failing.
		if await _switch_to_social("apple", identity_token):
			return true
		server_error.emit("link failed: %s" % res.get_exception().message)
		return false
	provider = "apple"
	save_settings()
	return true


## Links a Google id token to the current account.
func link_google(id_token: String) -> bool:
	if id_token.is_empty() or client == null or session == null:
		return false
	var res: NakamaAsyncResult = await client.link_google_async(session, id_token)
	if res.is_exception():
		# Already linked to another account (typically ours before a
		# reinstall): sign in to that one instead of failing.
		if await _switch_to_social("google", id_token):
			return true
		server_error.emit("link failed: %s" % res.get_exception().message)
		return false
	provider = "google"
	save_settings()
	return true


## Unlinks Apple. Nakama needs a fresh identity token to prove ownership, so
## one is requested from SocialTokens when none is passed.
func unlink_apple(identity_token: String = "") -> bool:
	var token := identity_token if not identity_token.is_empty() else SocialTokens.request_apple()
	if token.is_empty() or client == null or session == null:
		return false
	var res: NakamaAsyncResult = await client.unlink_apple_async(session, token)
	if res.is_exception():
		server_error.emit("unlink failed: %s" % res.get_exception().message)
		return false
	_forget_provider("apple")
	return true


## Unlinks Google; needs a fresh id token, requested when none is passed.
func unlink_google(id_token: String = "") -> bool:
	var token := id_token if not id_token.is_empty() else SocialTokens.request_google()
	if token.is_empty() or client == null or session == null:
		return false
	var res: NakamaAsyncResult = await client.unlink_google_async(session, token)
	if res.is_exception():
		server_error.emit("unlink failed: %s" % res.get_exception().message)
		return false
	_forget_provider("google")
	return true


func _forget_provider(name: String) -> void:
	if provider == name:
		provider = ""
		save_settings()


## Authenticates with an Apple identity token instead of the device id and
## opens the socket. The account is created if the Apple id is new.
func sign_in_with_apple(identity_token: String) -> bool:
	if identity_token.is_empty():
		connection_failed.emit("auth failed: no Apple token")
		return false
	return await _finish_social_sign_in("apple", await _social_session("apple", identity_token, true))


## Authenticates with a Google id token instead of the device id.
func sign_in_with_google(id_token: String) -> bool:
	if id_token.is_empty():
		connection_failed.emit("auth failed: no Google token")
		return false
	return await _finish_social_sign_in("google", await _social_session("google", id_token, true))


## A Nakama session for a provider token; `create` false only finds an
## existing account.
func _social_session(name: String, token: String, create: bool) -> NakamaSession:
	_make_client()
	if name == "apple":
		return await client.authenticate_apple_async(token, _create_username(), create)
	return await client.authenticate_google_async(token, _create_username(), create)


func _finish_social_sign_in(name: String, new_session: NakamaSession) -> bool:
	if new_session.is_exception():
		var msg := "auth failed: %s" % new_session.get_exception().message
		push_warning(msg)
		connection_failed.emit(msg)
		return false
	session = new_session
	if provider != name:
		provider = name
		save_settings()
	return await _open_socket()


## Signs in to the existing account a provider token belongs to, replacing
## the current (guest) session. False when the token has no account.
func _switch_to_social(name: String, token: String) -> bool:
	var found := await _social_session(name, token, false)
	if found.is_exception() or (session != null and found.user_id == session.user_id):
		return false
	_closing = true
	if socket != null:
		socket.close()
	_closing = false
	session = found
	provider = name
	save_settings()
	if not await _open_socket():
		return false
	account_switched.emit(name)
	return true


## Connects with the remembered provider when a token provider is available
## on this device, otherwise with the device id. The lobby calls this
## instead of connect_to_server at launch.
## WHY create=false and the fallback: a provider sign-in that fails (server
## misconfigured, provider unlinked on another phone) must not leave the
## player offline or make a new empty account; the device id still reaches
## the account that holds the progress.
func connect_preferred() -> bool:
	var avail: Dictionary = SocialTokens.available()
	var token := ""
	if provider == "apple" and avail.get("apple", false):
		token = SocialTokens.request_apple()
	elif provider == "google" and avail.get("google", false):
		token = SocialTokens.request_google()
	if not token.is_empty():
		var found := await _social_session(provider, token, false)
		if not found.is_exception():
			session = found
			return await _open_socket()
		push_warning("%s sign-in failed, using the device id: %s" % [provider, found.get_exception().message])
	return await connect_to_server()


# --- Shop, Remote Config and push ----------------------------------------------
# WHY the server decides: purchases are read from RevenueCat on the server
# (decision D5), Remote Config lives in Nakama storage, and push tokens are
# server-only rows. The device-side plugins are stubs until TODO-local G.

## After every sign-in: switches, the purchase plugin's user, the push token.
func _on_connected_services() -> void:
	Purchases.configure(user_id)
	await get_remote_config()
	await register_push_token()


## Applies and returns the server switches; {} when offline or on failure.
func get_remote_config() -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "get_remote_config", "{}")
	if rpc.is_exception():
		return {}
	var data = JSON.parse_string(rpc.payload)
	if not data is Dictionary:
		return {}
	RemoteConfig.apply(data)
	remote_config_updated.emit()
	return data


## Skins on sale: {configured, skins: [{id, slot, name, productId, owned}],
## owned}, or {} when offline or on failure.
func store_catalog() -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "store_catalog", "{}")
	if rpc.is_exception():
		return {}
	var data = JSON.parse_string(rpc.payload)
	return data if data is Dictionary else {}


## Asks the server to re-read this account's purchases from RevenueCat:
## {configured, owned, equipped, unlocked}, or {} on failure. Applies the
## equipped cosmetics (a refunded skin falls back to the default).
func sync_purchases() -> Dictionary:
	if client == null or session == null:
		return {}
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "sync_purchases", "{}")
	if rpc.is_exception():
		return {}
	var data = JSON.parse_string(rpc.payload)
	if not data is Dictionary:
		return {}
	Cosmetics.apply_equipped(data.get("equipped", {}))
	return data


## Sends this device's FCM token to the server when there is one. True when
## a token was registered.
func register_push_token() -> bool:
	if client == null or session == null:
		return false
	var token := PushTokens.request_token()
	if token.is_empty():
		return false
	var payload := JSON.stringify({"token": token, "platform": PushTokens.platform()})
	var rpc: NakamaAPI.ApiRpc = await client.rpc_async(session, "register_push_token", payload)
	return not rpc.is_exception()
