class_name SocialTokens
## Platform sign-in tokens for Sign in with Apple and Google Sign-In.
## Bottom layer: no references to Net or ui. `Net` turns the token into a
## Nakama session (sign_in_with_*) or links it to the guest account (link_*).
##
## TODO(owner): both `request_*` functions return "" until the native plugins
## are installed on a real machine (docs/TODO-local.md section E):
##   - iOS: a Sign in with Apple plugin for Godot 4 (for example the
##     "apple_signin" plugin from godot-ios-plugins, or GodotAppleSignIn).
##     Its callback returns the Apple *identity token* (a JWT string); return
##     that string from `request_apple()`. Nakama checks it with Apple's
##     public keys and needs `social.apple.bundle_id` set on the server.
##   - Android: the Google Sign-In plugin for Godot 4 (Credential Manager or
##     Play Games Services v2, for example godot-google-play-games-services
##     or GodotGoogleSignIn). Configure it with the OAuth *web* client id from
##     the Google Cloud console (the `.env` value GOOGLE_CLIENT_ID); its
##     callback returns the Google *id token* (a JWT string); return that from
##     `request_google()`. Nakama verifies it against Google's certificates.
## Register each plugin under the singleton names below (or change the names)
## so `available()` reports it and the lobby shows the button.

const PLUGIN_APPLE := "AppleSignIn"
const PLUGIN_GOOGLE := "GoogleSignIn"


## Which providers can hand us a token on this device: {apple, google}.
## A provider counts when its plugin singleton is registered; on the wrong
## platform a plugin that happens to be present is ignored (a desktop editor
## with an Android plugin folder must not show "Link Google").
static func available() -> Dictionary:
	var os_name := OS.get_name()
	return {
		"apple": os_name == "iOS" and Engine.has_singleton(PLUGIN_APPLE),
		"google": os_name == "Android" and Engine.has_singleton(PLUGIN_GOOGLE),
	}


## True on a phone platform, whether or not the plugin is installed yet.
static func is_mobile() -> bool:
	var os_name := OS.get_name()
	return os_name == "iOS" or os_name == "Android"


## The Apple identity token (JWT) from the native sheet, or "" when the
## plugin is missing or the player cancelled.
static func request_apple() -> String:
	if not Engine.has_singleton(PLUGIN_APPLE):
		return ""
	# TODO(owner): call the plugin here and await its signal; return the JWT.
	return ""


## The Google id token (JWT) from the account picker, or "" when the plugin
## is missing or the player cancelled.
static func request_google() -> String:
	if not Engine.has_singleton(PLUGIN_GOOGLE):
		return ""
	# TODO(owner): call the plugin here and await its signal; return the JWT.
	return ""
