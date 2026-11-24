class_name FounderPanel
extends PanelContainer
## Founder unlock: the player's own companies for the private rooms they
## host. Opened from the shop. Locked, it shows a sample company and the
## unlock (Buy and Restore). Unlocked, it shows the six companies as small
## shares; tapping one opens it in the editor: a live share at full size, the
## name, a colour from the palette and a drawn logo (or, for players 13 and
## older, their own logo picture, shown to others once reviewed). Each
## company keeps its share count, so the game plays the same; colours and
## logos another company already uses are shown taken, because the six at a
## table must differ in both (colourblind players tell them apart by shape).
## Built in code on the royal sheet like the quests; fed by
## `FounderApi.state()` through `apply_state`.

signal closed

## Px per design point for the sheet (same as the quests sheet).
const K := 1.35
const ROW_HEIGHT := 56.0
const CREAM := Color("#FFF6DE")
## Shown on the locked page so a player sees what they would make.
const SAMPLE := {"name": "Rocket Mail", "color": "teal", "logo": "rocket", "picture": null}
const PICTURE_STATUS := {
	"approved": "Your logo picture is live.",
	"pending": "Your logo picture is waiting for review. Until then others see the drawn logo.",
	"rejected": "That picture cannot be used. Others see the drawn logo.",
}

## The last founder_state answer.
var state: Dictionary = {}
## Company being edited (0..5).
var selected: int = 0
## The editor's working copy of the selected company:
## {name, color, logo, picture_hash, picture_status}.
var draft: Dictionary = {}
## Working copies by company index, so switching company keeps unsaved edits.
var drafts: Dictionary = {}
## True while a save is on its way, so Save cannot be sent twice.
var _saving := false
var _editor_note: Label
var _age_box: VBoxContainer
var _status: Label
var _locked_box: VBoxContainer
var _buy_button: Button
var _studio_box: VBoxContainer
var _use_toggle: CheckButton
var _minis: Array[CardView] = []
var _preview: CardView
var _share_note: Label
var _name_edit: LineEdit
var _swatches: Dictionary = {}
var _logo_tiles: Dictionary = {}
var _picture_tile: LogoTile
var _picture_note: Label
var _save_button: Button
var _reset_button: Button
var _crop_box: VBoxContainer
var _crop_preview: CardView
var _zoom: HSlider
var _crop_save: Button
var _picture: Image
var _center := Vector2(0.5, 0.5)
var _dragging := false
var _file_dialog: FileDialog


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.royal_sheet_style(K))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)
	var title := UiTheme.outlined("Your companies", 34, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", 14)
	scroll.add_child(pages)

	_build_locked(pages)
	_build_studio(pages)
	_build_crop(pages)

	_status = _text("", 19, UiTheme.LILAC)
	column.add_child(_status)
	var close := UiTheme.button("Close", 22, ROW_HEIGHT, "ghost")
	close.pressed.connect(_close)
	column.add_child(close)
	apply_state({})


# ---- Building -----------------------------------------------------------------

func _build_locked(parent: Control) -> void:
	_locked_box = VBoxContainer.new()
	_locked_box.add_theme_constant_override("separation", 14)
	parent.add_child(_locked_box)
	var plate := _plate()
	_locked_box.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	plate.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CardView.W * 1.3, CardView.H * 1.3)
	row.add_child(holder)
	var sample := CardView.new()
	sample.setup(-1, 2, 0, true)
	sample.preview_look = SAMPLE
	sample.scale = Vector2(1.3, 1.3)
	sample.rotation_degrees = -4
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sample)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 8)
	row.add_child(words)
	words.add_child(UiTheme.outlined("Found your own companies", 24))
	words.add_child(_text("Give any of the six companies your own name, colour and logo. Everyone in the private rooms you host plays with them.", 19, CREAM))
	words.add_child(_text("Share counts and rules never change.", 17, UiTheme.LILAC))
	_buy_button = UiTheme.button("Unlock Founder", 24, 64, "primary")
	_buy_button.pressed.connect(_on_buy)
	_locked_box.add_child(_buy_button)
	var restore := UiTheme.button("Restore purchases", 20, ROW_HEIGHT, "ghost")
	restore.pressed.connect(_on_restore)
	_locked_box.add_child(restore)


func _build_studio(parent: Control) -> void:
	_studio_box = VBoxContainer.new()
	_studio_box.add_theme_constant_override("separation", 14)
	parent.add_child(_studio_box)

	var use_plate := _plate()
	_studio_box.add_child(use_plate)
	_use_toggle = CheckButton.new()
	_use_toggle.text = "Use my companies in rooms I host"
	_use_toggle.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	# Flat: a switch on the plate, not a second violet button.
	_use_toggle.flat = true
	_use_toggle.add_theme_font_size_override("font_size", 20)
	_use_toggle.add_theme_color_override("font_color", CREAM)
	_use_toggle.add_theme_color_override("font_pressed_color", CREAM)
	_use_toggle.add_theme_color_override("font_hover_color", CREAM)
	_use_toggle.add_theme_color_override("font_hover_pressed_color", CREAM)
	_use_toggle.toggled.connect(_on_use_toggled)
	use_plate.add_child(_use_toggle)

	# The six companies as small shares; the selected one wears the orange ring.
	var minis := HBoxContainer.new()
	minis.alignment = BoxContainer.ALIGNMENT_CENTER
	minis.add_theme_constant_override("separation", 10)
	_studio_box.add_child(minis)
	for i in 6:
		var index := i
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(CardView.W * 0.74, CardView.H * 0.74)
		minis.add_child(holder)
		var mini := CardView.new()
		mini.setup(-1, i, 0, true)
		mini.scale = Vector2(0.74, 0.74)
		mini.card_pressed.connect(func(_id: int) -> void: select_company(index))
		holder.add_child(mini)
		_minis.append(mini)
	var hint := _text("Tap a share to make it yours.", 17, UiTheme.LILAC)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_box.add_child(hint)

	var editor := _plate()
	_studio_box.add_child(editor)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	editor.add_child(stack)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	stack.add_child(top)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CardView.W * 1.45, CardView.H * 1.45)
	top.add_child(holder)
	_preview = CardView.new()
	_preview.scale = Vector2(1.45, 1.45)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_preview)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	top.add_child(right)
	right.add_child(_heading("Name"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = Companies.NAME_MAX
	_name_edit.placeholder_text = "Your company"
	_name_edit.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text_changed.connect(func(t: String) -> void:
		draft["name"] = t
		_editor_note.text = ""
		_refresh_editor())
	right.add_child(_name_edit)
	_share_note = _text("", 17, UiTheme.LILAC)
	right.add_child(_share_note)

	stack.add_child(_heading("Colour"))
	var colours := HFlowContainer.new()
	colours.add_theme_constant_override("h_separation", 10)
	colours.add_theme_constant_override("v_separation", 10)
	stack.add_child(colours)
	for id in Companies.PALETTE_ORDER:
		var cid: String = id
		var sw := Swatch.new()
		sw.color_id = cid
		sw.pressed.connect(func() -> void: _pick_color(cid))
		colours.add_child(sw)
		_swatches[cid] = sw

	stack.add_child(_heading("Logo"))
	var logos := HFlowContainer.new()
	logos.add_theme_constant_override("h_separation", 10)
	logos.add_theme_constant_override("v_separation", 10)
	stack.add_child(logos)
	for id in Companies.LOGOS:
		var lid: String = id
		var tile := LogoTile.new()
		tile.logo = lid
		tile.pressed.connect(func() -> void: _pick_logo(lid))
		logos.add_child(tile)
		_logo_tiles[lid] = tile
	_picture_tile = LogoTile.new()
	_picture_tile.logo = ""
	_picture_tile.pressed.connect(_on_picture_tile)
	logos.add_child(_picture_tile)
	_picture_note = _text("", 17, UiTheme.LILAC)
	stack.add_child(_picture_note)
	_age_box = VBoxContainer.new()
	_age_box.add_theme_constant_override("separation", 8)
	_age_box.visible = false
	stack.add_child(_age_box)
	_age_box.add_child(_text("How old are you?", 20, CREAM))
	var ages := HBoxContainer.new()
	ages.add_theme_constant_override("separation", 8)
	_age_box.add_child(ages)
	for answer in [["Under 13", "under13"], ["13 to 15", "13to15"], ["16 or older", "16plus"]]:
		var bracket: String = answer[1]
		var b := UiTheme.button(answer[0], 18, ROW_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _on_age(bracket))
		ages.add_child(b)
	_editor_note = _text("", 18, UiTheme.GOLD_PALE)
	stack.add_child(_editor_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	stack.add_child(buttons)
	_reset_button = UiTheme.button("Use standard", 20, ROW_HEIGHT, "ghost")
	_reset_button.pressed.connect(_on_reset)
	buttons.add_child(_reset_button)
	_save_button = UiTheme.button("Save company", 22, ROW_HEIGHT, "primary")
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.pressed.connect(_on_save)
	buttons.add_child(_save_button)


func _build_crop(parent: Control) -> void:
	_crop_box = VBoxContainer.new()
	_crop_box.add_theme_constant_override("separation", 12)
	_crop_box.visible = false
	parent.add_child(_crop_box)
	_crop_box.add_child(_text("Drag the share to move your picture; use the slider to zoom.", 19, CREAM))
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, CardView.H * 2 + 16)
	_crop_box.add_child(center)
	var box := Control.new()
	box.custom_minimum_size = Vector2(CardView.W * 2, CardView.H * 2)
	box.gui_input.connect(_on_crop_input)
	center.add_child(box)
	_crop_preview = CardView.new()
	_crop_preview.scale = Vector2(2, 2)
	_crop_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_crop_preview)
	_zoom = HSlider.new()
	_zoom.min_value = 1.0
	_zoom.max_value = 4.0
	_zoom.step = 0.05
	_zoom.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_zoom.value_changed.connect(func(_v: float) -> void: _render_crop())
	_crop_box.add_child(_zoom)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_crop_box.add_child(buttons)
	var cancel := UiTheme.button("Cancel", 20, ROW_HEIGHT, "ghost")
	cancel.pressed.connect(close_crop)
	buttons.add_child(cancel)
	_crop_save = UiTheme.button("Use this logo", 22, ROW_HEIGHT, "primary")
	_crop_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crop_save.pressed.connect(_on_upload)
	buttons.add_child(_crop_save)
	_crop_box.add_child(_text("Only use a picture you made or may use. Pictures are checked before other players see them.", 17, UiTheme.LILAC))


func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.plate_style(K))
	return p


func _text(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", UiTheme.body_font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l


func _heading(text: String) -> Label:
	return UiTheme.outlined(text, 20)


# ---- State --------------------------------------------------------------------

## Shows the panel and loads the player's companies.
func open() -> void:
	visible = true
	drafts = {}
	close_crop()
	await refresh()


func refresh() -> void:
	if state.is_empty():
		_status.text = "Loading your companies..."
	var data: Dictionary = await FounderApi.state()
	if data.is_empty():
		apply_state({})
		_status.text = "Connect to the internet to edit your companies."
		return
	apply_state(data)
	await _fetch_own_pictures()
	if not data.get("owned", false):
		await _load_price()


## Feeds a founder_state answer: the unlock page or the studio. With no
## answer yet (loading, offline) neither shows, so an owner never sees the
## buy page flash.
func apply_state(data: Dictionary) -> void:
	state = data
	var known := not data.is_empty()
	var enabled: bool = data.get("enabled", true)
	var owned: bool = data.get("owned", false)
	_locked_box.visible = known and enabled and not owned and not _crop_box.visible
	_studio_box.visible = known and enabled and owned and not _crop_box.visible
	_buy_button.disabled = not Purchases.available()
	if known and not enabled:
		_status.text = "Custom companies are taking a short break. Yours are safe."
	elif known and not owned:
		_status.text = "A one-time unlock." if Purchases.available() else "Unlocking needs the App Store or Google Play app on a phone."
	elif known:
		_status.text = ""
	_use_toggle.set_pressed_no_signal(data.get("active", false))
	_age_box.visible = false
	# Companies only looked at follow the newly loaded row (a review may
	# have approved a picture); real edits are kept.
	for i in drafts.keys():
		if not is_dirty(i):
			drafts.erase(i)
	select_company(selected)


## Puts the store price on the unlock button when the store plugin gives one.
func _load_price() -> void:
	if not Purchases.available():
		return
	var product := String(state.get("productId", "bb_founder"))
	var prices: Dictionary = await Purchases.prices(PackedStringArray([product]))
	var price := String(prices.get(product, ""))
	_buy_button.text = "Unlock Founder  %s" % price if not price.is_empty() else "Unlock Founder"


## The saved company `i` ({name, color, logo, picture, pictureStatus}) or {} for the standard one.
func saved(i: int) -> Dictionary:
	var list: Array = state.get("companies", [])
	return list[i] if i < list.size() and list[i] is Dictionary else {}


## What company `i` looks like as saved (custom or standard): what the
## server checks a new company against.
func effective(i: int) -> Dictionary:
	var c := saved(i)
	if not c.is_empty():
		return {"name": String(c["name"]), "color": String(c["color"]), "logo": String(c["logo"])}
	var std: Dictionary = Companies.DATA[i]
	return {"name": String(std["name"]), "color": Companies.DEFAULT_COLOR_IDS[i], "logo": Companies.LOGOS[i]}


## The editor's copy of company `i`: unsaved edits when there are some.
func _draft_of(i: int) -> Dictionary:
	if drafts.has(i):
		return drafts[i]
	var c := saved(i)
	var base := effective(i)
	return {
		"name": base["name"], "color": base["color"], "logo": base["logo"],
		"picture_hash": String(c["picture"]) if c.get("picture") is String else "",
		"picture_status": String(c["pictureStatus"]) if c.get("pictureStatus") is String else "",
	}


## True when the editor's copy of company `i` differs from what is saved.
func is_dirty(i: int) -> bool:
	if not drafts.has(i):
		return false
	var d: Dictionary = drafts[i]
	var base := effective(i)
	var c := saved(i)
	var saved_pic := String(c["picture"]) if c.get("picture") is String else ""
	return d["name"] != base["name"] or d["color"] != base["color"] or d["logo"] != base["logo"] or d["picture_hash"] != saved_pic


## Opens company `i` in the editor. Unsaved edits of each company are kept
## while the player looks at another one.
func select_company(i: int) -> void:
	selected = clampi(i, 0, 5)
	draft = _draft_of(selected)
	drafts[selected] = draft
	_name_edit.text = draft["name"]
	_editor_note.text = ""
	_refresh_minis()
	_refresh_editor()


func _refresh_minis() -> void:
	for i in _minis.size():
		var d := _draft_of(i)
		_minis[i].preview_look = {"name": d["name"], "color": d["color"], "logo": d["logo"], "picture": _picture_texture(i)}
		_minis[i].highlight = i == selected


## The logo picture texture of company `i` in the editor, or null.
func _picture_texture(i: int) -> Texture2D:
	var h := String(_draft_of(i).get("picture_hash", ""))
	return CardArt.texture(h) if not h.is_empty() else null


func _refresh_editor() -> void:
	if draft.is_empty():
		return
	var std: Dictionary = Companies.DATA[selected]
	_preview.setup(-1, selected, 0, true)
	_preview.preview_look = {"name": draft["name"] if not String(draft["name"]).strip_edges().is_empty() else "Your company", "color": draft["color"], "logo": draft["logo"], "picture": _picture_texture(selected)}
	_minis[selected].preview_look = _preview.preview_look
	_share_note.text = "%d shares, in the place of %s." % [int(std["shares"]), String(std["name"])]
	# Taken: what another company has saved, counting too-alike pairs.
	var taken_colors := {}
	var taken_logos := {}
	for j in 6:
		if j != selected:
			var e := effective(j)
			taken_colors[Companies.family_of(Companies.COLOR_FAMILIES, e["color"])] = true
			taken_logos[Companies.family_of(Companies.LOGO_FAMILIES, e["logo"])] = true
	for id in _swatches:
		var sw: Swatch = _swatches[id]
		sw.chosen = id == draft["color"]
		sw.taken = taken_colors.has(Companies.family_of(Companies.COLOR_FAMILIES, id))
		sw.disabled = sw.taken
		sw.queue_redraw()
	var fill: Color = Companies.PALETTE.get(draft["color"], Companies.GOLD)
	var has_picture := not String(draft["picture_hash"]).is_empty()
	for id in _logo_tiles:
		var t: LogoTile = _logo_tiles[id]
		t.fill = fill
		# The drawn logo stays chosen under a picture: it is what others see until review.
		t.chosen = id == draft["logo"]
		t.taken = taken_logos.has(Companies.family_of(Companies.LOGO_FAMILIES, id))
		t.disabled = t.taken
		t.modulate = Color(1, 1, 1, 0.55) if t.taken else Color.WHITE
		t.queue_redraw()
	var blocker := String(state.get("uploadBlocker", ""))
	_picture_tile.texture = _picture_texture(selected)
	_picture_tile.chosen = has_picture
	_picture_tile.visible = blocker != "too_young"
	_picture_tile.disabled = blocker == "banned"
	_picture_tile.queue_redraw()
	_picture_note.text = _picture_text(blocker, has_picture)
	_picture_note.visible = not _picture_note.text.is_empty()
	_reset_button.disabled = saved(selected).is_empty()
	_reset_button.text = "Use standard"
	var n := String(draft["name"]).strip_edges()
	_save_button.disabled = _saving or n.length() < 2 or not is_dirty(selected)


func _picture_text(blocker: String, has_picture: bool) -> String:
	if blocker == "too_young":
		return "Pick a drawn logo. Your own pictures are for players 13 and older."
	if blocker == "banned":
		return "Picture uploads are off for this account."
	if has_picture:
		return PICTURE_STATUS.get(String(draft.get("picture_status", "")), "Your logo picture shows once you save the company.")
	if saved(selected).is_empty():
		return "Tap + to add your own logo picture."
	return ""


# ---- Editing ------------------------------------------------------------------

func _pick_color(id: String) -> void:
	draft["color"] = id
	_editor_note.text = ""
	_refresh_minis()
	_refresh_editor()


func _pick_logo(id: String) -> void:
	draft["logo"] = id
	# Picking a drawn logo stops using the picture (saved with the company).
	draft["picture_hash"] = ""
	draft["picture_status"] = ""
	_editor_note.text = ""
	_refresh_minis()
	_refresh_editor()


func _on_save() -> void:
	await save_draft()


## Saves the selected company's draft. True when it was saved.
func save_draft() -> bool:
	var n := String(draft.get("name", "")).strip_edges()
	_saving = true
	_save_button.disabled = true
	_status.text = "Saving..."
	var c := saved(selected)
	var had_picture := c.get("picture") is String and not String(c["picture"]).is_empty()
	var drop := had_picture and String(draft["picture_hash"]).is_empty()
	var res: Dictionary = await FounderApi.save(selected, n, String(draft["color"]), String(draft["logo"]), drop)
	_saving = false
	if res.is_empty():
		_status.text = ""
		# The reason sits right above the button, next to what it is about.
		_editor_note.text = FounderApi.last_error if not FounderApi.last_error.is_empty() else "Could not save. Try again."
		_refresh_editor()
		return false
	var keep := selected
	drafts.erase(keep)
	await refresh()
	select_company(keep)
	_pop(_minis[keep])
	_status.text = "%s is saved." % n if state.get("active", false) else "%s is saved. Switch on \"Use my companies\" to play with it." % n
	return true


## A saved company's small share bounces once: the save landed.
func _pop(card: CardView) -> void:
	var t := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(card, "scale", Vector2(0.82, 0.82), 0.12)
	t.tween_property(card, "scale", Vector2(0.74, 0.74), 0.18)


func _on_reset() -> void:
	_status.text = "Saving..."
	if await FounderApi.reset(selected):
		var keep := selected
		drafts.erase(keep)
		await refresh()
		select_company(keep)
		_status.text = "Back to %s." % String(Companies.DATA[keep]["name"])
	else:
		_editor_note.text = FounderApi.last_error
		_status.text = ""


func _on_use_toggled(on: bool) -> void:
	if await FounderApi.set_active(on):
		state["active"] = on
		_status.text = "Rooms you host use your companies." if on else "Rooms you host use the standard companies."
	else:
		_use_toggle.set_pressed_no_signal(not on)
		_status.text = FounderApi.last_error


func _on_buy() -> void:
	_status.text = "Opening the store..."
	if await Purchases.purchase(String(state.get("productId", "bb_founder"))):
		await Net.sync_purchases()
	await refresh()


func _on_restore() -> void:
	_status.text = "Restoring purchases..."
	if Purchases.available():
		await Purchases.restore()
	await Net.sync_purchases()
	await refresh()


## Own pictures still under review are served to their owner for the preview.
func _fetch_own_pictures() -> void:
	var want: Array[String] = []
	for c in state.get("companies", []):
		if c is Dictionary and c.get("picture") is String and CardArt.texture(String(c["picture"])) == null:
			want.append(String(c["picture"]))
	if not want.is_empty():
		await Net.fetch_card_art(want)
		_refresh_minis()
		_refresh_editor()


# ---- Logo picture -------------------------------------------------------------

func _on_picture_tile() -> void:
	var blocker := String(state.get("uploadBlocker", ""))
	if blocker == "age_unknown":
		# The neutral age question (D4), asked here so a Founder-only player
		# never has to find it in Designer.
		_age_box.visible = true
		return
	# A picture belongs to a saved company: save this one first (even unchanged).
	if saved(selected).is_empty() and not await save_draft():
		return
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Pick a logo", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
			func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
				if ok and paths.size() > 0:
					_load_picture(paths[0]))
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = filters
		_file_dialog.file_selected.connect(_load_picture)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.9)


## The age answer: refreshes the upload blocker and keeps the player's edits.
func _on_age(bracket: String) -> void:
	var res: Dictionary = await DesignerApi.set_age(bracket)
	if res.is_empty():
		_editor_note.text = DesignerApi.last_error
		return
	_age_box.visible = false
	var keep := selected
	await refresh()
	select_company(keep)
	if String(state.get("uploadBlocker", "")) == "":
		_on_picture_tile()


func _load_picture(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "That picture could not be opened. Try a PNG or JPEG."
		return
	open_crop(img)


## Frames `picture` as the selected company's logo; public so tests can skip the picker.
func open_crop(picture: Image) -> void:
	_picture = picture
	_center = Vector2(0.5, 0.5)
	_zoom.set_value_no_signal(1.0)
	_crop_box.visible = true
	_studio_box.visible = false
	_crop_save.disabled = false
	_crop_preview.setup(-1, selected, 0, true)
	_render_crop()
	_status.text = ""


func close_crop() -> void:
	_picture = null
	_crop_box.visible = false
	_studio_box.visible = state.get("owned", false) and state.get("enabled", true)


## The current framing rendered at the logo template size.
func rendered() -> Image:
	return CardArt.render(_picture, "logo", _zoom.value, _center)


func _render_crop() -> void:
	if _picture == null:
		return
	var tex := ImageTexture.create_from_image(rendered())
	_crop_preview.preview_look = {"name": draft.get("name", ""), "color": draft.get("color", "yellow"), "logo": draft.get("logo", "sun"), "picture": tex}


func _on_crop_input(event: InputEvent) -> void:
	if _picture == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		var rect := CardArt.crop_rect(_picture.get_size(), "logo", _zoom.value, _center)
		# The logo circle on the 2x preview is about 110 px across.
		var per_px := Vector2(rect.size) / Vector2(110, 110)
		_center -= event.relative * per_px / Vector2(_picture.get_size())
		_center = _center.clamp(Vector2.ZERO, Vector2.ONE)
		_render_crop()


func _on_upload() -> void:
	if _picture == null:
		return
	var bytes := CardArt.encode(rendered())
	if bytes.is_empty():
		_status.text = "That picture is too detailed to save. Try zooming in."
		return
	_crop_save.disabled = true
	_status.text = "Saving..."
	var res: Dictionary = await FounderApi.upload_logo(selected, bytes)
	_crop_save.disabled = false
	if res.is_empty():
		_status.text = FounderApi.last_error if not FounderApi.last_error.is_empty() else "Could not save. Try again."
		return
	close_crop()
	var keep := selected
	# The picture is saved; unsaved name, colour or logo edits stay unsaved.
	var edits: Dictionary = draft.duplicate()
	await refresh()
	drafts.erase(keep)
	var fresh := _draft_of(keep)
	edits["picture_hash"] = fresh["picture_hash"]
	edits["picture_status"] = fresh["picture_status"]
	drafts[keep] = edits
	select_company(keep)
	_status.text = "Your logo is live." if res.get("status") == "approved" else "Saved. Others see your picture once it has been reviewed; until then they see the drawn logo."


func _close() -> void:
	close_crop()
	visible = false
	closed.emit()


## The phone's back gesture closes the crop first, then the sheet.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		if _crop_box.visible:
			close_crop()
		else:
			_close()


# ---- Pickers ------------------------------------------------------------------

## A round colour swatch: gold ring when chosen, dimmed with an ink slash when
## another company already has the colour.
class Swatch extends BaseButton:
	var color_id := ""
	var chosen := false
	var taken := false

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 6.0
		if chosen:
			draw_circle(c, r + 6.0, UiTheme.GOLD)
		draw_circle(c, r + 2.5, UiTheme.OUTLINE)
		var col: Color = Companies.PALETTE.get(color_id, Color.WHITE)
		draw_circle(c, r, col if not taken else col.lerp(UiTheme.NIGHT, 0.55))
		# A soft highlight, like the glossy buttons.
		draw_circle(c - Vector2(r * 0.3, r * 0.35), r * 0.28, Color(1, 1, 1, 0.22 if not taken else 0.08))
		if taken:
			draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.6, -r * 0.6), UiTheme.OUTLINE, 4.0, true)
		if chosen:
			# A check in the band's text colour.
			var ink := Companies.text_on(color_id)
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, 0), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.45, -r * 0.3)]), ink, 4.5, true)


## A drawn logo on a cream tile, or the "your picture" tile (logo "").
class LogoTile extends BaseButton:
	var logo := ""
	var fill := Color.WHITE
	var chosen := false
	var taken := false
	var texture: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(72, 72)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var box := StyleBoxFlat.new()
		box.bg_color = Companies.CARD_FACE if not taken else Companies.CARD_FACE.lerp(UiTheme.NIGHT, 0.6)
		box.set_corner_radius_all(14)
		box.set_border_width_all(5 if chosen else 2)
		box.border_color = UiTheme.GOLD if chosen else UiTheme.OUTLINE
		box.anti_aliasing = true
		draw_style_box(box, r)
		var c := size / 2.0
		if logo.is_empty():
			if texture != null:
				CompanyLogos.draw_picture(self, texture, c, r.size.x * 0.68)
			else:
				# A plus in a dashed circle: add your own picture.
				var rad := r.size.x * 0.3
				for i in 16:
					if i % 2 == 0:
						draw_arc(c, rad, TAU * i / 16.0, TAU * (i + 1) / 16.0, 4, Companies.INK_SOFT, 2.5, true)
				draw_line(c - Vector2(rad * 0.5, 0), c + Vector2(rad * 0.5, 0), Companies.INK_SOFT, 3.5, true)
				draw_line(c - Vector2(0, rad * 0.5), c + Vector2(0, rad * 0.5), Companies.INK_SOFT, 3.5, true)
			return
		CompanyLogos.draw(self, logo, c, r.size.x * 0.74, fill if not taken else fill.lerp(Companies.INK_SOFT, 0.6))
