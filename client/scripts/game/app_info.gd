class_name AppInfo
## Contact details the stores require every app to publish (Apple
## guideline 1.2, Google Play's user-generated content and families
## policies). The Help screen shows them; fill both before any public build.

## Address players can write to about problems or other players.
const SUPPORT_EMAIL := ""
## Public page with the privacy policy.
const PRIVACY_URL := ""


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


static func has_contact() -> bool:
	return not SUPPORT_EMAIL.is_empty() and not PRIVACY_URL.is_empty()
