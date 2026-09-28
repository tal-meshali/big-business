class_name HelpScreen
extends Control
## Help overlay for the lobby: a replayable rules reference in player
## language, "Replay the tutorial", support contact, privacy policy and the
## version. Built in code on the deed-panel look, inside a ScrollContainer so
## it fits any phone height. Every button is at least 48 px tall.
##
## The rules text is written from docs/design/rules-spec.md in our own words
## (decision D1: nothing from the source game's publisher is named).

signal closed

## Rules reference, one entry per section, in the order shown.
const SECTIONS := [
	{
		"title": "Goal",
		"body": "Six companies are up for grabs. Collect their shares. On dividend day, whoever holds the most shares of a company gets paid by everyone else who holds that company. The player with the most capital at the end wins.",
	},
	{
		"title": "A turn: take, then play",
		"body": "Every turn has two steps. First take one share: draw from the supply, or pick one up from the Market. Then play one share from your hand: keep it in your portfolio (face up, it counts toward majorities) or sell it to the Market.\n\nOne rule: you can't sell the company you just took.",
	},
	{
		"title": "Drawing costs coins",
		"body": "Before you draw from the supply, put 1 coin on every share sitting in the Market (skip the companies whose regulator token you hold). If you can't pay for all of them, you can't draw.\n\nTaking from the Market is free, and you pocket every coin on that share.",
	},
	{
		"title": "The Market",
		"body": "Shares sold to the Market sit face up, with whatever coins have been placed on them. Anyone can take one on their turn, except a company whose regulator token they hold. A share with coins on it is free money for whoever grabs it first.",
	},
	{
		"title": "Regulator tokens",
		"body": "After every play, the player with strictly the most shares of a company in their portfolio holds that company's regulator token. On a tie the token stays where it is.\n\nWhile you hold a token you pay nothing onto that company's Market shares when you draw, but you can't take that company from the Market. Tokens never limit what you play.",
	},
	{
		"title": "The end and dividend day",
		"body": "When the last supply share is drawn, the game ends after that player's turn. Everyone's three hand cards join their portfolio, so they count.\n\nThen, for each company, the sole majority holder collects 1 coin per share from every other holder of that company. A tie for the most pays nothing. Coins received as dividends turn gold and are worth 3 each.\n\nScore: 1 per bronze coin plus 3 per gold coin. Ties go to more gold, then to the leaner portfolio.",
	},
	{
		"title": "Timers and bots",
		"body": "Public games give you 30 seconds per step. Private rooms can choose 20, 30, 60 or 120 seconds, or no timer. When time runs out, the server makes a sensible move for you. Miss three turns in a row and a bot takes your seat until you come back.\n\nA table has 3 to 7 seats; empty seats are filled by bots, and a private room for two adds one bot.",
	},
]

## Called by "Replay the tutorial"; the lobby provides it.
var on_replay: Callable = Callable()

var replay_button: Button
var support_button: Button
var privacy_button: Button
var close_button: Button
var version_label: Label
var _section_titles: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_right = -24
	scroll.offset_top = 48
	scroll.offset_bottom = -32
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backdrop.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)

	# Rules reference on a blue deed.
	var rules := UiTheme.deed_panel(Companies.CHEST, "How to play", Color.WHITE)
	rules["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rules_box := VBoxContainer.new()
	rules_box.add_theme_constant_override("separation", 10)
	rules["body"].add_child(rules_box)
	for section in SECTIONS:
		var title := Label.new()
		title.text = section["title"]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 21)
		rules_box.add_child(title)
		_section_titles.append(title)
		var body := Label.new()
		body.text = section["body"]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 17)
		body.add_theme_color_override("font_color", Companies.INK_SOFT)
		rules_box.add_child(body)
	replay_button = _button(rules_box, "Replay the tutorial", _on_replay)
	column.add_child(rules["panel"])

	# Contact, privacy and version on a gold deed.
	var about := UiTheme.deed_panel(Companies.GOLD, "About", Companies.INK)
	about["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var about_box := VBoxContainer.new()
	about_box.add_theme_constant_override("separation", 10)
	about["body"].add_child(about_box)
	var contact := Label.new()
	contact.text = "Questions, problems or a report to follow up? Write to %s" % AppInfo.SUPPORT_EMAIL
	contact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about_box.add_child(contact)
	support_button = _button(about_box, "Contact support", _on_support)
	privacy_button = _button(about_box, "Privacy policy", _on_privacy)
	version_label = Label.new()
	version_label.text = "Big Business %s" % AppInfo.VERSION
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Companies.INK_SOFT)
	about_box.add_child(version_label)
	column.add_child(about["panel"])

	close_button = _button(column, "Close", _on_close)
	close_button.custom_minimum_size = Vector2(0, 56)


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


## Section headings in display order (used by the smoke test).
func section_titles() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _section_titles:
		out.append(t.text)
	return out


func _on_replay() -> void:
	_on_close()
	if on_replay.is_valid():
		on_replay.call()


func _on_support() -> void:
	OS.shell_open("mailto:" + AppInfo.SUPPORT_EMAIL)


func _on_privacy() -> void:
	OS.shell_open(AppInfo.PRIVACY_URL)


func _on_close() -> void:
	visible = false
	closed.emit()
