class_name HelpScreen
extends Control
## Rules reference and contact details, opened from the lobby's Help button
## or the "?" button at the table. A scrollable deed panel over a dimmed
## backdrop; closing it returns to wherever it was opened.

signal closed

## The rules in short, in the same words as docs/design/rules-spec.md.
const SECTIONS := [
	{
		"title": "The goal",
		"body": "Collect shares in six companies. When the game ends, whoever holds the most shares of a company collects a dividend from everyone else who holds it. Most capital wins.",
	},
	{
		"title": "Your turn: take, then play",
		"body": "Every turn has two steps. First take one share: draw the top share of the supply, or pick a share from the Market. Then play one share from your hand: keep it in your portfolio, or sell it to the Market.",
	},
	{
		"title": "Drawing costs coins",
		"body": "Before you draw, put 1 coin on every share in the Market, except companies whose regulator token you hold. If you can't pay, you can't draw.\n\nTaking a share from the Market is free, and you collect every coin on it.",
	},
	{
		"title": "Selling to the Market",
		"body": "A share you sell goes into the Market with no coins on it. You can't sell a share of the company you took this turn.",
	},
	{
		"title": "Regulator tokens",
		"body": "Whoever has strictly the most shares of a company in their portfolio holds its token. On a tie the token stays where it is.\n\nWith a token you pay nothing onto that company's Market shares when drawing, but you can't take that company from the Market.",
	},
	{
		"title": "The end of the game",
		"body": "When the last supply share is drawn, that player finishes their turn and the game ends. Every hand joins its owner's portfolio, so the shares you are holding count.",
	},
	{
		"title": "Dividend day",
		"body": "For each company, the sole majority holder collects 1 coin per share from every other player who holds that company. A tie for the most pays nothing.\n\nCoins received as dividends turn gold and are worth 3. Other coins are worth 1.",
	},
	{
		"title": "Who wins",
		"body": "The most capital wins. Ties go to more gold coins, then to fewer shares in the portfolio.",
	},
]

var _email_button: Button
var _privacy_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	backdrop.add_child(margin)
	var deed := UiTheme.deed_panel(Companies.CHEST, "How Big Business works", Color.WHITE)
	margin.add_child(deed["panel"])
	# The deed body only takes its minimum height unless told to fill, which
	# would collapse the scroll area to nothing.
	deed["body"].size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	deed["body"].add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	for section in SECTIONS:
		_add_section(content, section["title"], section["body"])
	var sizes := PackedStringArray()
	for c in Companies.DATA:
		sizes.append("%s: %d" % [c["name"], c["shares"]])
	_add_section(content, "The companies", "Shares issued per company. Five shares are set aside unseen at the start of every game.\n\n" + "\n".join(sizes))

	_add_heading(content, "Help and privacy")
	_add_body(content, "During a game, tap another player's seat to mute, report or block them. Reports go to our moderators.")
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 12)
	content.add_child(links)
	_email_button = _make_button(links, "Email support", func() -> void: OS.shell_open("mailto:" + AppInfo.SUPPORT_EMAIL))
	_email_button.disabled = AppInfo.SUPPORT_EMAIL.is_empty()
	_privacy_button = _make_button(links, "Privacy policy", func() -> void: OS.shell_open(AppInfo.PRIVACY_URL))
	_privacy_button.disabled = AppInfo.PRIVACY_URL.is_empty()
	var version := _add_body(content, "Big Business %s" % AppInfo.version())
	version.add_theme_color_override("font_color", Companies.INK_SOFT)
	version.add_theme_font_size_override("font_size", 14)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(close_help)
	column.add_child(close)


func _add_section(parent: Control, title: String, body: String) -> void:
	_add_heading(parent, title)
	_add_body(parent, body)


func _add_heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 21)
	parent.add_child(l)


func _add_body(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Companies.INK)
	parent.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	parent.add_child(gap)
	return l


func _make_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func close_help() -> void:
	closed.emit()
	queue_free()


## Opens the help overlay on top of `parent` and returns it.
static func open_over(parent: Control) -> HelpScreen:
	var help := HelpScreen.new()
	parent.add_child(help)
	return help
