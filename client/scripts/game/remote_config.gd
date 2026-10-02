class_name RemoteConfig
## Server-side switches from the `get_remote_config` RPC
## (server/src/match/remote_config.ts). The defaults match the server's, so
## the lobby behaves the same before the first answer arrives or offline.

const DEFAULTS := {
	"shopEnabled": true,
	"pushEnabled": true,
	"tutorialAutoRoute": false,
}

static var shop_enabled: bool = DEFAULTS["shopEnabled"]
static var push_enabled: bool = DEFAULTS["pushEnabled"]
## Send a brand-new player's first "Play now" to the tutorial.
static var tutorial_auto_route: bool = DEFAULTS["tutorialAutoRoute"]


## Applies a server answer; keys that are missing or of the wrong type keep
## their current value.
static func apply(data: Dictionary) -> void:
	if data.get("shopEnabled") is bool:
		shop_enabled = data["shopEnabled"]
	if data.get("pushEnabled") is bool:
		push_enabled = data["pushEnabled"]
	if data.get("tutorialAutoRoute") is bool:
		tutorial_auto_route = data["tutorialAutoRoute"]


static func reset() -> void:
	shop_enabled = DEFAULTS["shopEnabled"]
	push_enabled = DEFAULTS["pushEnabled"]
	tutorial_auto_route = DEFAULTS["tutorialAutoRoute"]
