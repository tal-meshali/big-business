class_name PushTokens
## Device token for "your turn" pushes through Firebase Cloud Messaging.
## Bottom layer: no references to Net or ui. `Net` registers the token with
## the server (register_push_token) after each sign-in.
##
## TODO(owner): `request_token()` returns "" until the native plugins are
## installed on a real machine (docs/TODO-local.md G):
##   - A Firebase Messaging plugin for Godot 4 on Android and iOS (for
##     example GodotFirebase's messaging module, or a small custom plugin),
##     registered under the singleton name below, with the app's
##     google-services.json / GoogleService-Info.plist from the Firebase project.
##   - Ask for notification permission first (Android 13+ POST_NOTIFICATIONS,
##     iOS UNUserNotificationCenter) with a short in-game explanation, never
##     at first launch.
##   - Return the FCM registration token; call `Net.register_push_token()`
##     again when the plugin reports a refreshed token.

const PLUGIN := "FirebaseMessaging"


static func available() -> bool:
	var os_name := OS.get_name()
	return (os_name == "iOS" or os_name == "Android") and Engine.has_singleton(PLUGIN)


## "android" or "ios" for the server; "" elsewhere.
static func platform() -> String:
	match OS.get_name():
		"Android":
			return "android"
		"iOS":
			return "ios"
	return ""


## The FCM registration token, or "" when the plugin is missing, the player
## declined notifications, or the token is not ready yet.
static func request_token() -> String:
	if not available():
		return ""
	# TODO(owner): ask the plugin for the token (after the permission prompt).
	return ""
