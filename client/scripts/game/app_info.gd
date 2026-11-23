class_name AppInfo
## Contact details the stores require every app to publish (Apple
## guideline 1.2, Google Play's user-generated content and families
## policies). The Help screen shows them; fill both before any public build.

## Address players can write to about problems or other players.
const SUPPORT_EMAIL := ""
## Public page with the privacy policy.
const PRIVACY_URL := ""

## The deployed server (docs/home-server.md: the home Windows PC through
## Tailscale Funnel; Fly.io before that), for builds handed to players:
## the address the lobby starts with until the player types another one,
## and its NAKAMA_SERVER_KEY from .env (embedded in the app, not a secret).
## Empty keeps the local default, 127.0.0.1 with "defaultkey". Editor runs and
## tests always start on the local server.
const SERVER_ADDRESS := "https://desktop-j5t74pv.taild5bda7.ts.net"
const SERVER_KEY := "35bd519ec107d4960bf69ce4042b98e83d5d125cd146ce9dbacc29638de1cfed"


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


static func has_contact() -> bool:
	return not SUPPORT_EMAIL.is_empty() and not PRIVACY_URL.is_empty()
