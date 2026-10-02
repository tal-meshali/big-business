class_name DesignerPanel
extends PanelContainer
## Designer unlock (decision D5): the player's own card art for private
## rooms. Opened from the shop. Shows, in order of what is missing: the
## unlock (Buy and Restore), the neutral age question (decision D4), then
## three deck slots with a row per part (card back and six art windows).
## Picking a picture opens the crop editor: the picture is framed at the
## part's fixed aspect with zoom and drag, previewed on a real card, then
## rendered and uploaded through CardArt and DesignerApi. Pictures show to
## other players only once approved.

signal closed

const ROW_HEIGHT := 48.0
const PART_NAMES := {"back": "Card back"}
const STATUS_TEXT := {
	"approved": "Live",
	"pending": "Waiting for review",
	"rejected": "Not allowed",
}

## The last designer_state answer.
var state: Dictionary = {}
## Deck slot being edited.
var slot: int = 0
var _status: Label
var _unlock_box: VBoxContainer
var _buy_button: Button
var _age_box: VBoxContainer
var _blocked_label: Label
var _deck_box: VBoxContainer
var _slot_buttons: Array[Button] = []
var _use_toggle: CheckButton
var _parts_list: VBoxContainer
var _show_toggle: CheckButton
var _editor: VBoxContainer
var _preview: CardView
var _zoom: HSlider
var _upload_button: Button
## The picture being framed, its part, and the framing.
var _picture: Image
var _part: String = ""
var _center := Vector2(0.5, 0.5)
var _dragging: bool = false
var _file_dialog: FileDialog


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.deed_panel(Companies.CHANCE, "Designer", Color.WHITE)
	deed["title"].add_theme_font_size_override("font_size", 28)
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var body: MarginContainer = deed["body"]
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)

	var intro := _label("Put your own pictures on the cards in private rooms you host. The card frame, company and share count always stay the same, so the game reads the same for everyone.")
	column.add_child(intro)

	_unlock_box = VBoxContainer.new()
	_unlock_box.add_theme_constant_override("separation", 8)
	column.add_child(_unlock_box)
	_buy_button = _button("Unlock Designer", _on_buy)
	_unlock_box.add_child(_buy_button)
	_unlock_box.add_child(_button("Restore purchases", _on_restore))

	_age_box = VBoxContainer.new()
	_age_box.add_theme_constant_override("separation", 8)
	column.add_child(_age_box)
	_age_box.add_child(_label("How old are you?"))
	for answer in [["Under 13", "under13"], ["13 to 15", "13to15"], ["16 or older", "16plus"]]:
		var bracket: String = answer[1]
		_age_box.add_child(_button(answer[0], func() -> void: _on_age(bracket)))

	_blocked_label = _label("")
	column.add_child(_blocked_label)

	_deck_box = VBoxContainer.new()
	_deck_box.add_theme_constant_override("separation", 8)
	column.add_child(_deck_box)
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 8)
	_deck_box.add_child(slots_row)
	for i in 3:
		var index := i
		var b := _button("Deck %d" % (i + 1), func() -> void: _on_slot(index))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots_row.add_child(b)
		_slot_buttons.append(b)
	_use_toggle = CheckButton.new()
	_use_toggle.text = "Use this deck in rooms I create"
	_use_toggle.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_use_toggle.toggled.connect(_on_use_toggled)
	_deck_box.add_child(_use_toggle)
	_parts_list = VBoxContainer.new()
	_parts_list.add_theme_constant_override("separation", 6)
	_deck_box.add_child(_parts_list)
	_deck_box.add_child(_label("Pictures are checked before other players see them. Only use pictures you made or have the right to use; pictures that break the rules are removed, and repeat breaks end uploads."))

	_editor = VBoxContainer.new()
	_editor.add_theme_constant_override("separation", 10)
	_editor.visible = false
	column.add_child(_editor)
	_editor.add_child(_label("Drag the card to move the picture; use the slider to zoom."))
	var preview_holder := CenterContainer.new()
	preview_holder.custom_minimum_size = Vector2(0, CardView.H * 2 + 16)
	_editor.add_child(preview_holder)
	var preview_box := Control.new()
	preview_box.custom_minimum_size = Vector2(CardView.W * 2, CardView.H * 2)
	preview_box.gui_input.connect(_on_preview_input)
	preview_holder.add_child(preview_box)
	_preview = CardView.new()
	_preview.scale = Vector2(2, 2)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.add_child(_preview)
	_zoom = HSlider.new()
	_zoom.min_value = 1.0
	_zoom.max_value = 4.0
	_zoom.step = 0.05
	_zoom.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_zoom.value_changed.connect(func(_v: float) -> void: _render_preview())
	_editor.add_child(_zoom)
	var editor_buttons := HBoxContainer.new()
	editor_buttons.add_theme_constant_override("separation", 8)
	_editor.add_child(editor_buttons)
	_upload_button = _button("Save", _on_upload)
	_upload_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_buttons.add_child(_upload_button)
	var cancel := _button("Cancel", close_editor)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_buttons.add_child(cancel)

	_show_toggle = CheckButton.new()
	_show_toggle.text = "Show other players' custom cards"
	_show_toggle.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_show_toggle.button_pressed = CardArt.show_custom
	_show_toggle.toggled.connect(func(on: bool) -> void:
		CardArt.show_custom = on
		CardArt.save_settings())
	column.add_child(_show_toggle)

	_status = _label("")
	_status.add_theme_color_override("font_color", Companies.INK_SOFT)
	column.add_child(_status)
	column.add_child(_button("Close", func() -> void:
		close_editor()
		visible = false
		closed.emit()))
	apply_state({})


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 18)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	b.pressed.connect(handler)
	return b


## Shows the panel and loads the player's Designer state.
func open() -> void:
	visible = true
	await refresh()


func refresh() -> void:
	_status.text = "Loading..."
	var data: Dictionary = await DesignerApi.state()
	if data.is_empty():
		apply_state({})
		_status.text = "Connect to use Designer."
		return
	apply_state(data)
	await _fetch_own_previews()


## Feeds a designer_state answer and shows the step that is missing.
func apply_state(data: Dictionary) -> void:
	state = data
	var blocker := String(data.get("blocker", "offline" if data.is_empty() else ""))
	_unlock_box.visible = blocker == "not_owned"
	_buy_button.disabled = not Purchases.available()
	_age_box.visible = blocker == "age_unknown"
	_blocked_label.visible = blocker == "too_young" or blocker == "banned"
	_blocked_label.text = "Uploading pictures is not available at your age. You can still play with custom cards in private rooms." if blocker == "too_young" else "Uploads are switched off for this account because pictures broke the rules."
	_deck_box.visible = blocker == "" and int(data.get("slots", 0)) > 0
	if not data.get("enabled", true):
		_deck_box.visible = false
		_status.text = "Designer is taking a short break. Your decks are safe."
	elif blocker == "not_owned":
		_status.text = "A one-time unlock. Custom cards show in private rooms you host." if Purchases.available() else "Unlocking needs the App Store or Google Play app on a phone."
	else:
		_status.text = ""
	slot = clampi(slot, 0, maxi(0, int(data.get("slots", 1)) - 1))
	_refresh_deck()


func _refresh_deck() -> void:
	for i in _slot_buttons.size():
		_slot_buttons[i].button_pressed = i == slot
		_slot_buttons[i].visible = i < int(state.get("slots", 0))
	_use_toggle.set_pressed_no_signal(int(state.get("active", -1)) == slot)
	for child in _parts_list.get_children():
		child.queue_free()
	var decks: Array = state.get("decks", [])
	if slot >= decks.size():
		return
	var deck: Dictionary = decks[slot]
	for part in CardArt.PARTS:
		var hash = deck.get("back") if part == "back" else deck.get("art", [])[int(part.substr(1))]
		var st = deck.get("backStatus") if part == "back" else deck.get("artStatus", [])[int(part.substr(1))]
		_add_part_row(part, hash if hash is String else "", st if st is String else "")


func _add_part_row(part: String, hash: String, status: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_parts_list.add_child(row)
	var name_label := _label("%s\n%s" % [part_name(part), STATUS_TEXT.get(status, "Standard") if not hash.is_empty() else "Standard"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var pick := _button("Picture", func() -> void: _pick_picture(part))
	pick.custom_minimum_size = Vector2(120, ROW_HEIGHT)
	row.add_child(pick)
	var clear := _button("Clear", func() -> void: _on_clear(part))
	clear.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	clear.disabled = hash.is_empty()
	row.add_child(clear)


static func part_name(part: String) -> String:
	if PART_NAMES.has(part):
		return PART_NAMES[part]
	return "%s art" % Companies.short_name_of(int(part.substr(1)))


## Own pictures still under review are served to their owner, so the
## preview can show them; approved ones come from the cache or the server.
func _fetch_own_previews() -> void:
	var want: Array[String] = []
	for deck in state.get("decks", []):
		for h in [deck.get("back")] + Array(deck.get("art", [])):
			if h is String and CardArt.texture(h) == null and not want.has(h) and want.size() < CardArt.PARTS.size():
				want.append(h)
	if not want.is_empty():
		await Net.fetch_card_art(want)


func _on_slot(index: int) -> void:
	slot = index
	close_editor()
	_refresh_deck()


func _on_use_toggled(on: bool) -> void:
	var target := slot if on else -1
	if await DesignerApi.select_deck(target):
		state["active"] = target
		_status.text = "Rooms you create will use Deck %d." % (slot + 1) if on else "Rooms you create will use the standard cards."
	else:
		_use_toggle.set_pressed_no_signal(not on)
		_status.text = DesignerApi.last_error


func _on_age(bracket: String) -> void:
	var res: Dictionary = await DesignerApi.set_age(bracket)
	if res.is_empty():
		_status.text = DesignerApi.last_error
		return
	await refresh()


func _on_buy() -> void:
	var product := String(state.get("productId", "bb_designer"))
	_status.text = "Opening the store..."
	if await Purchases.purchase(product):
		await Net.sync_purchases()
	await refresh()


func _on_restore() -> void:
	_status.text = "Restoring purchases..."
	if Purchases.available():
		await Purchases.restore()
	await Net.sync_purchases()
	await refresh()


func _on_clear(part: String) -> void:
	if await DesignerApi.clear_part(slot, part):
		await refresh()
	else:
		_status.text = DesignerApi.last_error


## Opens the system picture picker (or Godot's on desktop).
func _pick_picture(part: String) -> void:
	_part = part
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Pick a picture", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
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


func _load_picture(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "That picture could not be opened. Try a PNG or JPEG."
		return
	open_editor(img, _part)


## Frames `picture` for `part`; public so tests can skip the file picker.
func open_editor(picture: Image, part: String) -> void:
	_picture = picture
	_part = part
	_center = Vector2(0.5, 0.5)
	_zoom.set_value_no_signal(1.0)
	_editor.visible = true
	_deck_box.visible = false
	_upload_button.disabled = false
	if part == "back":
		_preview.setup(-1, 0, 0, false)
	else:
		_preview.setup(-1, int(part.substr(1)), 0, true)
	_render_preview()
	_status.text = "Framing the %s." % part_name(part).to_lower()


func close_editor() -> void:
	_picture = null
	_preview.preview_back = null
	_preview.preview_art = null
	_editor.visible = false
	_deck_box.visible = not state.is_empty() and String(state.get("blocker", "")) == "" and int(state.get("slots", 0)) > 0


## The current framing rendered at the part's template size.
func rendered() -> Image:
	return CardArt.render(_picture, _part, _zoom.value, _center)


func _render_preview() -> void:
	if _picture == null:
		return
	var tex := ImageTexture.create_from_image(rendered())
	_preview.preview_back = tex if _part == "back" else null
	_preview.preview_art = null if _part == "back" else tex
	_preview.queue_redraw()


## Dragging the preview moves the picture under the frame.
func _on_preview_input(event: InputEvent) -> void:
	if _picture == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		var rect := CardArt.crop_rect(_picture.get_size(), _part, _zoom.value, _center)
		# One preview pixel covers this many picture pixels.
		var shown := Vector2(CardView.W * 2, CardView.H * 2) if _part == "back" else Vector2(88 * 2, 46 * 2)
		var per_px := Vector2(rect.size) / shown
		_center -= event.relative * per_px / Vector2(_picture.get_size())
		_center = _center.clamp(Vector2.ZERO, Vector2.ONE)
		_render_preview()


func _on_upload() -> void:
	if _picture == null:
		return
	var bytes := CardArt.encode(rendered())
	if bytes.is_empty():
		_status.text = "That picture is too detailed to save. Try zooming in."
		return
	_upload_button.disabled = true
	_status.text = "Saving..."
	var res: Dictionary = await DesignerApi.upload(slot, _part, bytes)
	_upload_button.disabled = false
	if res.is_empty():
		_status.text = DesignerApi.last_error if not DesignerApi.last_error.is_empty() else "Could not save. Try again."
		return
	close_editor()
	await refresh()
	_status.text = "Saved. It shows in your rooms now." if res.get("status") == "approved" else "Saved. Others see it once it has been reviewed; until then they see the standard card."
