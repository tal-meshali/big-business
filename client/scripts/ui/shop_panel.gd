class_name ShopPanel
extends PanelContainer
## Skin shop overlay for the lobby: curated card backs and table felts sold
## a la carte for real money (decision D5: no virtual currency), each with
## Buy or Use, plus Restore Purchases (required by both stores). Built in
## code on a deed panel and fed by `Net.store_catalog()` through
## `apply_catalog`. Buying goes through `Purchases` (the store plugin);
## what the player owns always comes back from the server. The Designer
## unlock (custom card art) and the stats open their own panels over this
## one; the Plus subscription row shows only while Remote Config offers it.

signal closed
## Emitted after a skin is put on, once `Cosmetics` already reflects it.
signal cosmetic_changed(slot: String, id: String)

const ROW_HEIGHT := 48.0

## One entry per skin: {id, slot, product_id, name, button, label}.
var rows: Array[Dictionary] = []
var owned: Array = []
## Localised price strings by product id, from the store plugin.
var prices: Dictionary = {}
var _list: VBoxContainer
var _status: Label
var _restore_button: Button
var _designer_button: Button
var designer_panel: DesignerPanel
var stats_panel: StatsPanel
var _plus_box: VBoxContainer
var _plus_label: Label
var _plus_button: Button
## The Plus row from the catalog ({} when not offered).
var plus: Dictionary = {}
var _deed_panel: Control


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.deed_panel(Companies.GOLD, "Shop", Companies.INK)
	deed["title"].add_theme_font_size_override("font_size", 28)
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var body: MarginContainer = deed["body"]
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(column)

	var intro := Label.new()
	intro.text = "Card backs and table felts. Skins only change the look, never the game."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	column.add_child(intro)

	_designer_button = Button.new()
	_designer_button.text = "Designer: your own card art"
	_designer_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_designer_button.visible = RemoteConfig.designer_enabled
	_designer_button.pressed.connect(_on_open_designer)
	column.add_child(_designer_button)

	_plus_box = VBoxContainer.new()
	_plus_box.add_theme_constant_override("separation", 6)
	_plus_box.visible = false
	column.add_child(_plus_box)
	_plus_label = Label.new()
	_plus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plus_label.add_theme_font_size_override("font_size", 18)
	_plus_box.add_child(_plus_label)
	var plus_row := HBoxContainer.new()
	plus_row.add_theme_constant_override("separation", 8)
	_plus_box.add_child(plus_row)
	_plus_button = Button.new()
	_plus_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_plus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plus_button.pressed.connect(_on_plus)
	plus_row.add_child(_plus_button)
	var stats_button := Button.new()
	stats_button.text = "Your stats"
	stats_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	stats_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_button.pressed.connect(_on_open_stats)
	plus_row.add_child(stats_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 17)
	_status.text = "Connect to see the shop."
	column.add_child(_status)

	_restore_button = Button.new()
	_restore_button.text = "Restore purchases"
	_restore_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_restore_button.pressed.connect(_on_restore)
	column.add_child(_restore_button)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)

	# A PanelContainer stacks its children, so the Designer covers the shop.
	designer_panel = DesignerPanel.new()
	designer_panel.visible = false
	_deed_panel = deed["panel"]
	designer_panel.closed.connect(func() -> void: _deed_panel.visible = true)
	add_child(designer_panel)
	stats_panel = StatsPanel.new()
	stats_panel.visible = false
	stats_panel.closed.connect(func() -> void: _deed_panel.visible = true)
	add_child(stats_panel)


## Shows the panel and loads the catalog and prices.
func open() -> void:
	visible = true
	_designer_button.visible = RemoteConfig.designer_enabled
	await refresh()


func _on_open_designer() -> void:
	_deed_panel.visible = false
	await designer_panel.open()


func _on_open_stats() -> void:
	_deed_panel.visible = false
	await stats_panel.open()


static func _owns_plus(data: Dictionary) -> bool:
	return Array(data.get("owned", [])).has("plus")


## Shows the Plus row from a catalog's unlocks: Subscribe, or active.
func _apply_plus(unlocks: Array) -> void:
	plus = {}
	for u in unlocks:
		if u is Dictionary and u.get("id") == "plus":
			plus = u
	_plus_box.visible = not plus.is_empty()
	if plus.is_empty():
		return
	var price := String(prices.get(String(plus.get("productId", "")), ""))
	if plus.get("owned", false):
		_plus_label.text = "Plus is active: ten Designer decks, your deck in quick play, a new skin each month, your stats, and your skins on the whole table in rooms you host. Manage it in your App Store or Google Play account."
		_plus_button.text = "Plus active"
		_plus_button.disabled = true
	else:
		_plus_label.text = "Plus%s: ten Designer decks, your deck in quick play, a new skin each month, full stats, and your skins on the whole table in rooms you host." % ((" (%s a month)" % price) if not price.is_empty() else "")
		_plus_button.text = "Subscribe"
		_plus_button.disabled = not Purchases.available()


func _on_plus() -> void:
	if plus.is_empty():
		return
	_plus_button.disabled = true
	_status.text = "Opening the store..."
	if await Purchases.purchase(String(plus.get("productId", ""))):
		await _sync("Welcome to Plus!")
	else:
		_status.text = ""
	await refresh()


func refresh() -> void:
	var data: Dictionary = await Net.store_catalog()
	if data.is_empty():
		_status.text = "Connect to see the shop."
		return
	apply_catalog(data)
	if Purchases.available():
		var ids := PackedStringArray()
		for r in rows:
			ids.append(r["product_id"])
		if not plus.is_empty():
			ids.append(String(plus.get("productId", "")))
		prices = await Purchases.prices(ids)
		_refresh_rows()
		_apply_plus([plus])


## Feeds a `store_catalog` result: {configured, skins: [...], owned: [...]}.
func apply_catalog(data: Dictionary) -> void:
	owned = data.get("owned", [])
	for r in rows:
		r["row"].queue_free()
	rows.clear()
	for skin in data.get("skins", []):
		_add_row(skin)
	_apply_plus(data.get("unlocks", []) if RemoteConfig.plus_enabled or _owns_plus(data) else [])
	if not data.get("configured", false):
		_status.text = "The shop opens soon. Anything you buy later can be restored here."
	elif not Purchases.available():
		_status.text = "Buying needs the App Store or Google Play app on a phone."
	else:
		_status.text = "Prices are in your local currency."
	_refresh_rows()


func _add_row(skin: Dictionary) -> void:
	var id := String(skin.get("id", ""))
	var slot := String(skin.get("slot", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_list.add_child(row)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(ROW_HEIGHT, ROW_HEIGHT)
	swatch.color = Cosmetics.swatch_color(id)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var label := Label.new()
	label.text = "%s  (%s)" % [Cosmetics.name_of(id), "card back" if slot == "cardBack" else "table felt"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(140, ROW_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: _on_action(id))
	row.add_child(button)
	rows.append({"id": id, "slot": slot, "product_id": String(skin.get("productId", "")), "button": button, "label": label, "row": row})


func _current(slot: String) -> String:
	return Cosmetics.card_back if slot == "cardBack" else Cosmetics.table


## Equipped skins read "In use", owned ones "Use", the rest "Buy" with the
## store price when the plugin gave one (disabled without the plugin).
func _refresh_rows() -> void:
	for r in rows:
		var b: Button = r["button"]
		var id: String = r["id"]
		if owned.has(id):
			var in_use := _current(r["slot"]) == id
			b.text = "In use" if in_use else "Use"
			b.disabled = in_use
		else:
			var price := String(prices.get(r["product_id"], ""))
			b.text = "Buy %s" % price if not price.is_empty() else "Buy"
			b.disabled = not Purchases.available()


func _row_by_id(id: String) -> Dictionary:
	for r in rows:
		if r["id"] == id:
			return r
	return {}


func _on_action(id: String) -> void:
	var r := _row_by_id(id)
	if r.is_empty():
		return
	if owned.has(id):
		await _use(r)
	else:
		await _buy(r)


## Puts an owned skin on at once, then tells the server; a refusal reverts.
func _use(r: Dictionary) -> void:
	var slot: String = r["slot"]
	var id: String = r["id"]
	if not Cosmetics.set_slot(slot, id):
		return
	_refresh_rows()
	cosmetic_changed.emit(slot, id)
	var res: Dictionary = await Net.equip_cosmetic(slot, id)
	if not res.is_empty() and not res.get("ok", false):
		Cosmetics.apply_equipped(res.get("equipped", {}))
		_status.text = "That skin is not on this account. Try Restore purchases."
		_refresh_rows()
		cosmetic_changed.emit(slot, _current(slot))


func _buy(r: Dictionary) -> void:
	if not Purchases.available():
		_status.text = "Buying needs the App Store or Google Play app on a phone."
		return
	var b: Button = r["button"]
	b.disabled = true
	_status.text = "Opening the store..."
	if not await Purchases.purchase(r["product_id"]):
		_status.text = "Purchase not completed."
		_refresh_rows()
		return
	await _sync("Thanks! %s is yours." % Cosmetics.name_of(r["id"]))


## Restore purchases: the store resends past purchases to RevenueCat, then
## the server reads them back. Works with or without the plugin, because a
## purchase made on another device is already known to RevenueCat.
func _on_restore() -> void:
	_restore_button.disabled = true
	_status.text = "Restoring purchases..."
	if Purchases.available():
		await Purchases.restore()
	await _sync("")
	_restore_button.disabled = false


func _sync(success_text: String) -> void:
	var before := owned.size()
	var res: Dictionary = await Net.sync_purchases()
	if res.is_empty():
		_status.text = "Could not reach the store. Try again in a moment."
		_refresh_rows()
		return
	apply_owned(res.get("owned", []))
	if not res.get("configured", false):
		_status.text = "The shop opens soon. Nothing to restore yet."
	elif not success_text.is_empty():
		_status.text = success_text
	elif owned.size() > before:
		_status.text = "Restored %d purchase%s." % [owned.size(), "" if owned.size() == 1 else "s"]
	else:
		_status.text = "Your purchases are up to date."


## Updates ownership from a server answer (a refund removes a skin here too).
func apply_owned(new_owned: Array) -> void:
	owned = new_owned
	_refresh_rows()
	cosmetic_changed.emit("table", Cosmetics.table)
