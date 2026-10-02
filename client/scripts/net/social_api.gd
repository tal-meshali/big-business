class_name SocialApi
## Gift and watch RPCs (server/src/match/rpc_gifts.ts, rpc_watch.ts) for the
## friends panel. Like DesignerApi, every call answers {} when offline or
## refused, with the server's message in `last_error`.

static var last_error: String = ""


static func _call(id: String, body: Dictionary) -> Dictionary:
	var res: Dictionary = await DesignerApi._call(id, body)
	last_error = DesignerApi.last_error
	return res


## {waiting, names, claimLeft, sentToday: [userId], sendLeft, points}.
static func gift_state() -> Dictionary:
	return await _call("gift_state", {})


static func send_gift(user_id: String) -> bool:
	return not (await _call("send_gift", {"userId": user_id})).is_empty()


## {claimed, points, trackPoints, unlocked, waiting}.
static func claim_gifts() -> Dictionary:
	return await _call("claim_gifts", {})


## User ids of mutual friends in a game that can be watched now.
static func friends_playing() -> Array:
	return (await _call("friends_playing", {})).get("playing", [])
