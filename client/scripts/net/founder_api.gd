class_name FounderApi
## Founder RPCs (server/src/match/rpc_founder.ts) for the Founder screen:
## the player's own companies (name, colour, logo) for the private rooms
## they host. Every call answers {} (or false) when offline or refused, with
## the server's message in `last_error`, so the screen can say what went wrong.

static var last_error: String = ""


static func _call(id: String, body: Dictionary) -> Dictionary:
	last_error = ""
	if Net.client == null or Net.session == null:
		last_error = "Not connected"
		return {}
	var rpc: NakamaAPI.ApiRpc = await Net.client.rpc_async(Net.session, id, JSON.stringify(body))
	if rpc.is_exception():
		last_error = DesignerApi.clean_error(rpc.get_exception().message)
		return {}
	var data = JSON.parse_string(rpc.payload)
	return data if data is Dictionary else {}


## {enabled, owned, productId, ageBracket, uploadBlocker, banned, companies: [6], active, colors, logos, logoTemplate}.
static func state() -> Dictionary:
	return await _call("founder_state", {})


## Saves company `index` (0..5). Keeps its logo picture unless `drop_picture`.
## Answers {company} or {} with the reason in `last_error`.
static func save(index: int, company_name: String, color: String, logo: String, drop_picture := false) -> Dictionary:
	var body := {"company": index, "name": company_name, "color": color, "logo": logo}
	if drop_picture:
		body["picture"] = null
	return await _call("save_company", body)


## Puts the standard company back in slot `index`.
static func reset(index: int) -> bool:
	return not (await _call("save_company", {"company": index, "reset": true})).is_empty()


## Uploads a logo picture rendered by CardArt.render(…, "logo") and encoded
## by CardArt.encode: {hash, status} where status is "approved" or "pending".
static func upload_logo(index: int, webp: PackedByteArray) -> Dictionary:
	var res := await _call("upload_company_logo", {"company": index, "image": Marshalls.raw_to_base64(webp)})
	if res.has("hash"):
		CardArt.add_art(String(res["hash"]), Marshalls.raw_to_base64(webp))
	return res


## Shows (or stops showing) the companies in private rooms this player hosts.
static func set_active(on: bool) -> bool:
	return not (await _call("set_companies_active", {"on": on})).is_empty()
