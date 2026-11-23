class_name CapitalChip
## Capital, drawn the way the visual direction draws it: a glossy minted
## coin (copper for capital, gold for dividends) with a dark rim and a lip
## underneath, and the count beside it in Archivo Black: ink on light
## surfaces, cream with an ink outline on dark ones. Seats, Market shares
## and flying coins all paint coins through here, so every coin on the
## table is the same object.
##
## A count that changes "ticks" like the design's .cap: the number swells
## and flashes gold while the coin and word stay put, so nothing around it
## moves.

## The design's tick: the count grows to 1.35x; the coin nudges a little.
const NUMBER_POP := 0.35
const COIN_POP := 0.12
## Coin radius and gap before the count, as parts of the chip's height.
const COIN_R := 0.56
const PAD := 0.2
## Count and word sizes, as parts of the height.
const NUMBER_PX := 0.95
const WORD_PX := 0.55
## Gap between the count and its word.
const WORD_GAP := 0.3
## Text outline, as a part of the text size (the buttons' and deltas' 0.3).
const OUTLINE_K := 0.3
## Side of the baked face texture in px.
const FACE_PX := 96

## Baked coin faces, one per metal.
static var _faces: Dictionary = {}


## A coin of radius `r` centred on `c`. `lip` draws the dark drop below it.
static func coin(ci: CanvasItem, c: Vector2, r: float, gold := false, lip := true) -> void:
	var rim := UiTheme.COIN_GOLD_RIM if gold else UiTheme.COPPER_RIM
	var o := maxf(1.5, r * 0.13)
	if lip:
		ci.draw_circle(c + Vector2(0, r * 0.2), r, UiTheme.OUTLINE, true, -1.0, true)
	ci.draw_circle(c, r, rim, true, -1.0, true)
	var face := r - o
	ci.draw_texture_rect(_face(gold), Rect2(c - Vector2(face, face), Vector2(face, face) * 2.0), false)
	# A minted inner ring, so it reads as a coin and not a ball.
	ci.draw_arc(c, face * 0.72, 0.0, TAU, 32, Color(rim, 0.3), maxf(1.0, r * 0.08), true)


## The coin's face: the design's radial-gradient(circle at 35% 30%,
## pale, mid 55%, deep) in a soft-edged disc.
## WHY baked: Godot has no radial fill for draw_circle, and stacked
## circles band visibly at badge size.
static func _face(gold: bool) -> ImageTexture:
	if _faces.has(gold):
		return _faces[gold]
	var stops: Array = [UiTheme.GOLD_PALE, UiTheme.GOLD, UiTheme.COIN_GOLD_DEEP] if gold else [UiTheme.COPPER_PALE, UiTheme.COPPER, UiTheme.COPPER_DEEP]
	var img := Image.create(FACE_PX, FACE_PX, false, Image.FORMAT_RGBA8)
	var n := float(FACE_PX)
	var spot := Vector2(0.35, 0.3) * n
	# CSS sizes the gradient to the farthest corner.
	var reach := spot.distance_to(Vector2(n, n))
	var mid := n / 2.0
	for y in FACE_PX:
		for x in FACE_PX:
			var p := Vector2(x + 0.5, y + 0.5)
			var t := p.distance_to(spot) / reach
			var col: Color = stops[0].lerp(stops[1], t / 0.55) if t < 0.55 else stops[1].lerp(stops[2], (t - 0.55) / 0.45)
			col.a = clampf(mid - p.distance_to(Vector2(mid, mid)) + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_faces[gold] = tex
	return tex


## Width of a coin and its count (and an optional `word`) at height `h`,
## at rest.
## WHY no room for the swell: the word fades out of its way during a tick,
## and the gap to the next chip takes a two-digit swell.
static func width(count: int, word: String, h: float) -> float:
	var w := h * COIN_R * 2.0 + PAD * h + _text_width(str(count), int(h * NUMBER_PX))
	if word != "":
		w += WORD_GAP * h + _text_width(word, int(h * WORD_PX))
	return w + h * 0.1


## How far past its chip's resting right edge a count reaches mid-tick
## (0 when the word beside it takes the swell).
static func swell_reach(count: int, word: String, h: float, pop: float) -> float:
	if UiTheme.reduce_motion():
		return 0.0
	var reach := _text_width(str(count), int(h * NUMBER_PX)) * NUMBER_POP * pop - h * 0.1
	if word != "":
		reach -= WORD_GAP * h + _text_width(word, int(h * WORD_PX))
	return maxf(0.0, reach)


static func _outline(px: int) -> int:
	return maxi(3, int(px * OUTLINE_K))


## Draws a coin whose left edge is at `at`.x, centred on `at`.y, with the
## count beside it in Archivo Black, straight on the surface `on` (no
## backing). On a light surface the count is solid ink; on a dark one it
## is cream with an ink outline, like the design's labels on colour. `pop`
## (0 to 1) swells the count and the coin and flashes the count gold.
## Returns the rect it covers.
## Assumes the canvas item draws with no transform of its own set.
static func draw(ci: CanvasItem, at: Vector2, count: int, word: String, h: float, gold := false, pop := 0.0, on: Color = UiTheme.CREAM) -> Rect2:
	# WHY 0.5 on the sRGB value: it splits every surface in play cleanly
	# (white plates about 0.95, royal about 0.13, the active violet about 0.3).
	var light := on.get_luminance() > 0.5
	var w := width(count, word, h)
	var r := h * COIN_R
	# Reduced motion keeps the gold flash and drops the swell.
	var swell := 0.0 if UiTheme.reduce_motion() else pop
	var cc := Vector2(at.x + r, at.y)
	coin(ci, cc, r * (1.0 + COIN_POP * swell), gold)
	var font := UiTheme.display_font()
	var npx := int(h * NUMBER_PX)
	var num := str(count)
	var nw := _text_width(num, npx)
	var x := cc.x + r + PAD * h
	var base := at.y + npx * 0.36
	if word != "":
		var wpx := int(h * WORD_PX)
		var wat := Vector2(x + nw + WORD_GAP * h, base)
		# The word is quieter than the count on either surface, and steps
		# aside (fades) while the count swells over it.
		var fade := 1.0 - clampf(swell * 1.6, 0.0, 1.0)
		if light:
			ci.draw_string(font, wat, word, HORIZONTAL_ALIGNMENT_LEFT, -1, wpx, Color(UiTheme.OUTLINE, 0.65 * fade))
		elif fade > 0.0:
			ci.draw_string_outline(font, wat, word, HORIZONTAL_ALIGNMENT_LEFT, -1, wpx, _outline(wpx), Color(UiTheme.OUTLINE, fade))
			ci.draw_string(font, wat, word, HORIZONTAL_ALIGNMENT_LEFT, -1, wpx, Color(UiTheme.LILAC, fade))
	# The count swells out of the coin (from its left edge, so it never
	# runs back over the coin) and turns gold at the peak.
	var k := 1.0 + NUMBER_POP * swell
	var pivot := Vector2(x, at.y)
	if swell > 0.0:
		ci.draw_set_transform(pivot * (1.0 - k), 0.0, Vector2(k, k))
	var flash := clampf(pop * 1.6, 0.0, 1.0)
	var col := (UiTheme.OUTLINE if light else UiTheme.CREAM).lerp(UiTheme.GOLD, flash)
	# On light, an opaque outline grows in with the flash so the gold stays
	# readable (a see-through one turns the glyph edges muddy).
	var edge := _outline(npx) if not light else int(_outline(npx) * clampf(flash * 2.0, 0.0, 1.0))
	if edge > 0:
		ci.draw_string_outline(font, Vector2(x, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, npx, edge, UiTheme.OUTLINE)
	ci.draw_string(font, Vector2(x, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, npx, col)
	if swell > 0.0:
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
	ci.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(3, int(r * 0.28)), UiTheme.COPPER_RIM)
	ci.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)


static func _text_width(text: String, px: int) -> float:
	return UiTheme.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
