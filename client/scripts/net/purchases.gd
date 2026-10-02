class_name Purchases
## Store purchases for the skin shop through the RevenueCat plugin.
## Bottom layer: no references to Net or ui. The server never trusts the
## device: after a purchase or a restore, `Net.sync_purchases()` asks the
## server to read the entitlements from RevenueCat itself.
##
## TODO(owner): every function below is a stub until the RevenueCat plugin
## is installed on a real machine (docs/TODO-local.md G):
##   - Install a RevenueCat plugin for Godot 4 that wraps purchases-android
##     and purchases-ios (or the official Purchases Hybrid SDK through a
##     Godot plugin), registered under the singleton name below.
##   - Configure it with the RevenueCat *public* app keys (.env:
##     REVENUECAT_APPLE_KEY / REVENUECAT_GOOGLE_KEY), never the secret key.
##   - `configure(app_user_id)` must log in with the Nakama user id, so the
##     server can look the player up by that id.
##   - Create the products bb_skin_back_gilded, bb_skin_back_blueprint and
##     bb_skin_table_walnut (non-consumable) in both stores, and in
##     RevenueCat the entitlements skin_<id> attached to them.

const PLUGIN := "RevenueCat"


## True when the plugin is present on a phone; the shop disables Buy otherwise.
static func available() -> bool:
	var os_name := OS.get_name()
	return (os_name == "iOS" or os_name == "Android") and Engine.has_singleton(PLUGIN)


## Logs the plugin in as this Nakama user. Call after every sign-in.
static func configure(app_user_id: String) -> void:
	if not available() or app_user_id.is_empty():
		return
	# TODO(owner): Engine.get_singleton(PLUGIN).logIn(app_user_id) (plugin API).


## Localised prices by product id, e.g. {"bb_skin_back_gilded": "$2.99"};
## {} when the plugin is missing (the shop then shows no price).
static func prices(_product_ids: PackedStringArray) -> Dictionary:
	if not available():
		return {}
	# TODO(owner): fetch the store products and return their price strings.
	await (Engine.get_main_loop() as SceneTree).process_frame
	return {}


## Opens the store sheet for one product. True when the store reports a
## completed purchase; false when cancelled, failed or unavailable.
static func purchase(_product_id: String) -> bool:
	if not available():
		return false
	# TODO(owner): call the plugin's purchase and await its result signal.
	await (Engine.get_main_loop() as SceneTree).process_frame
	return false


## Restore Purchases (required by both stores): asks the store to resend
## past purchases to RevenueCat. True when the plugin finished.
static func restore() -> bool:
	if not available():
		return false
	# TODO(owner): call the plugin's restorePurchases and await its signal.
	await (Engine.get_main_loop() as SceneTree).process_frame
	return false
