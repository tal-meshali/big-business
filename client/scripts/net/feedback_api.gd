class_name FeedbackApi
## Feedback to the team (server/src/match/feedback.ts): a bug, an idea or
## anything else, sent from More > Send feedback. Only the team reads it;
## other players never see it. Device details go only when the player
## leaves them switched on, and the sheet shows exactly what they are.

const CATEGORIES := ["bug", "idea", "other"]
const MIN_LENGTH := 3
## Same limit as the server's FEEDBACK_TEXT_MAX.
const MAX_LENGTH := 1000

const TOO_SHORT := "Write a few words first."
const OFFLINE := "You're offline. Keep this open, connect, then send."
const BUSY := "That's a lot of messages at once. Wait a minute, then send."
const DAILY := "That's today's limit of messages. Thank you for so many! Try again tomorrow."
const FAILED := "Couldn't send. Try again in a moment."


## Trimmed and without invisible characters, as the server will store it
## (server/src/match/feedback.ts cleanFeedbackText).
static func clean(typed: String) -> String:
	var out := typed
	# Joiners (U+200C, U+200D) stay: emoji families and Persian words need them.
	for code in [0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069]:
		out = out.replace(String.chr(code), "")
	return out.strip_edges()


## Why the typed text cannot be sent yet; "" when it can.
static func problem(typed: String) -> String:
	var visible := clean(typed).replace(String.chr(0x200c), "").replace(String.chr(0x200d), "").strip_edges()
	return TOO_SHORT if visible.length() < MIN_LENGTH else ""


## What "device details" means on this phone: {app, os, model, screen}.
## Nothing that names the player: no account, no address, no location.
static func device_details() -> Dictionary:
	var screen := DisplayServer.screen_get_size()
	var model := OS.get_model_name()
	var out := {
		"app": AppInfo.version(),
		"os": ("%s %s" % [OS.get_name(), OS.get_version()]).strip_edges(),
		"screen": "%dx%d" % [screen.x, screen.y],
	}
	# Desktops answer "GenericDevice": no model worth sending.
	if not model.is_empty() and model != "GenericDevice":
		out["model"] = model
	return out


## The details as one line, exactly what is sent.
static func describe(details: Dictionary) -> String:
	var parts: Array[String] = ["Big Business %s" % details.get("app", "")]
	for key in ["os", "model", "screen"]:
		if details.has(key):
			parts.append(String(details[key]))
	return " · ".join(parts)


## Sends one message. Answers "" when the team has it, otherwise the
## sentence to show the player.
static func send(category: String, text: String, with_details: bool) -> String:
	var early := problem(text)
	if not early.is_empty():
		return early
	if not Net.is_connected_to_server():
		return OFFLINE
	var body := {
		"category": category if CATEGORIES.has(category) else "other",
		"text": clean(text).left(MAX_LENGTH),
	}
	if with_details:
		body["device"] = device_details()
	var res: Dictionary = await DesignerApi._call("send_feedback", body)
	if res.get("ok", false):
		return ""
	return _message(DesignerApi.last_error)


static func _message(server_said: String) -> String:
	match server_said:
		"Not connected":
			return OFFLINE
		"too many requests":
			return BUSY
		"daily limit":
			return DAILY
	if server_said.ends_with(".") and server_said.length() < 80:
		return server_said
	return FAILED
