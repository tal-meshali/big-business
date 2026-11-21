class_name CapitalChip
## Capital, drawn the way the visual direction draws it: a glossy minted
## coin (copper for capital, gold for dividends) with a dark rim and a lip
## underneath, and the count in Archivo Black on a dark pill the coin sits
## on. Seats, Market shares and flying coins all paint coins through here,
## so every coin on the table is the same object.
## WHY concentric circles: Godot has no radial gradient fill for
## draw_circle; a few offset circles fake the design's
## radial-gradient(circle at 35% 30%, light, mid, dark).

const COPPER := [Color("#7A3E10"), Color("#C7742E"), Color("#FFE7C4")]
const COPPER_RIM := Color("#3A1A00")
const GOLD := [Color("#C77A00"), Color("#FFC83D"), Color("#FFF1B0")]
const GOLD_RIM := Color("#6B3A00")
## Text on the pill, and the colour a count flashes to when it changes.
const TEXT := Color("#FFF6DE")
const FLASH := Color("#FFC83D")
## How much a changed count swells at the top of its pop (1.3x, as the
## design's "tick").
const POP_SCALE := 0.3
## Steps in the faked radial gradient.
const STEPS := 7


## A coin of radius `r` centred on `c`. `lip` draws the dark drop below it.
static func coin(ci: CanvasItem, c: Vector2, r: float, gold := false, lip := true) -> void:
	var ramp: Array = GOLD if gold else COPPER
	var rim: Color = GOLD_RIM if gold else COPPER_RIM
	var o := maxf(1.5, r * 0.13)
	if lip:
		ci.draw_circle(c + Vector2(0, r * 0.2), r, UiTheme.OUTLINE, true, -1.0, true)
	ci.draw_circle(c, r, rim, true, -1.0, true)
	var face := r - o
	# Dark edge to a bright spot up and to the left (35% 30% in the design).
	var spot := c + Vector2(-0.3, -0.4) * face
	for i in STEPS:
		var t := float(i) / float(STEPS - 1)
		var col: Color = ramp[0].lerp(ramp[1], t * 2.0) if t < 0.5 else ramp[1].lerp(ramp[2], (t - 0.5) * 2.0)
		var rad := face * (1.0 - t * 0.82)
		ci.draw_circle(c.lerp(spot, t * 0.9) if i > 0 else c, rad, col, true, -1.0, true)
	# A minted inner ring, so it reads as a coin and not a ball.
	ci.draw_arc(c, face * 0.7, 0.0, TAU, 32, Color(rim, 0.35), maxf(1.0, r * 0.09), true)


## Width of a pill for `count` (and an optional `word`) at height `h`.
static func pill_width(count: int, word: String, h: float) -> float:
	var r := h * 0.62
	var w := r * 2.0 + h * 0.18 + _text_width(str(count), int(h * 0.8))
	if word != "":
		w += h * 0.22 + _text_width(word, int(h * 0.5))
	return w + h * 0.42


## A pill whose left coin is centred at (`at`.x + coin radius, `at`.y).
## `pop` (0 to 1) scales the pill up around its centre and flashes the
## count gold. Returns the pill's rect, unscaled.
static func pill(ci: CanvasItem, at: Vector2, count: int, word: String, h: float, gold := false, pop := 0.0) -> Rect2:
	var w := pill_width(count, word, h)
	var r := h * 0.62
	var box := Rect2(at.x + r * 0.6, at.y - h / 2.0, w - r * 0.6, h)
	var center := Vector2(at.x + w / 2.0, at.y)
	var k := 1.0 + POP_SCALE * pop
	if pop > 0.0:
		ci.draw_set_transform(center * (1.0 - k), 0.0, Vector2(k, k))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.OUTLINE
	sb.set_corner_radius_all(int(h / 2.0))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, box)
	# A faint top highlight, like the glossy buttons.
	ci.draw_line(Vector2(box.position.x + r * 1.2, box.position.y + h * 0.16), Vector2(box.end.x - h * 0.4, box.position.y + h * 0.16), Color(1, 1, 1, 0.14), maxf(1.0, h * 0.08), true)
	var cc := Vector2(at.x + r, at.y)
	coin(ci, cc, r, gold)
	var font := UiTheme.display_font()
	var npx := int(h * 0.8)
	var x := cc.x + r + h * 0.18
	var base := at.y + npx * 0.36
	var col := TEXT.lerp(FLASH, clampf(pop * 1.6, 0.0, 1.0))
	var num := str(count)
	ci.draw_string(font, Vector2(x, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, npx, col)
	if word != "":
		x += _text_width(num, npx) + h * 0.22
		var wpx := int(h * 0.5)
		ci.draw_string(font, Vector2(x, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, wpx, Color(TEXT, 0.72))
	if pop > 0.0:
		ci.draw_set_transform(Vector2.ZERO)
	return Rect2(at.x, at.y - h / 2.0, w, h)


## A count over a coin, outlined so it reads on any card art.
static func badge(ci: CanvasItem, c: Vector2, r: float, count: int) -> void:
	coin(ci, c, r)
	var font := UiTheme.display_font()
	var px := int(r * 1.05)
	var txt := str(count)
	var w := _text_width(txt, px)
	var at := c + Vector2(-w / 2.0, px * 0.36)
	ci.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(3, int(r * 0.28)), COPPER_RIM)
	ci.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)


static func _text_width(text: String, px: int) -> float:
	return UiTheme.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
