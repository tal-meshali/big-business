class_name AppInfo
## Contact details the stores require every app to publish (Apple
## guideline 1.2, Google Play's user-generated content and families
## policies). The Help screen shows them; fill both before any public build.

## Address players can write to about problems or other players.
const SUPPORT_EMAIL := ""
## Public page with the privacy policy.
const PRIVACY_URL := ""

## The deployed server (docs/deploy.md), for builds handed to players:
## the address the lobby starts with until the player types another one,
## and its NAKAMA_SERVER_KEY from .env (embedded in the app, not a secret).
## Empty keeps the local default, 127.0.0.1 with "defaultkey".
const SERVER_ADDRESS := ""
const SERVER_KEY := ""


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


static func has_contact() -> bool:
	return not SUPPORT_EMAIL.is_empty() and not PRIVACY_URL.is_empty()
