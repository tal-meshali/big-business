class_name NamesApi
## The player's name (server/src/match/rpc_names.ts): the one name other
## players see, picked at first launch and changed from the profile. The
## server owns the rules (server/src/match/names.ts); the length is checked
## here too so the field can say so before a round trip.

const MIN_LENGTH := 3
const MAX_LENGTH := 16

const TOO_SHORT := "Use at least 3 characters."
const OFFLINE := "Connect to save your name."
const BUSY := "Too many tries. Wait a minute and try again."
const FAILED := "Could not save your name. Try again."


## Trimmed, with runs of spaces collapsed, as the server will store it.
static func clean(typed: String) -> String:
	var out := typed.strip_edges()
	for blank in ["\t", "\n", "\r"]:
		out = out.replace(blank, " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out


## Why a typed name cannot be sent yet, as a sentence for the player; ""
## when it can (the server may still refuse it).
static func problem(typed: String) -> String:
	return TOO_SHORT if clean(typed).length() < MIN_LENGTH else ""


## Gives the account this name. Answers "" when it is saved, otherwise the
## sentence to show under the field.
static func save(typed: String) -> String:
	var wanted := clean(typed)
	var early := problem(wanted)
	if not early.is_empty():
		return early
	var res: Dictionary = await DesignerApi._call("set_name", {"name": wanted})
	if res.is_empty():
		return _message(DesignerApi.last_error)
	Net.display_name = String(res.get("name", wanted))
	Net.save_settings()
	await Net.refresh_identity()
	return ""


## The server's refusals are already sentences for the player; anything
## else (offline, rate limit, an outage) gets one here.
static func _message(server_said: String) -> String:
	if server_said == "Not connected":
		return OFFLINE
	if server_said == "too many requests":
		return BUSY
	if server_said.ends_with(".") and server_said.length() < 80:
		return server_said
	return FAILED
