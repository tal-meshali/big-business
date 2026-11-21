class_name TableBoard
extends Control
## The felt table, tilted away from the player like a real table seen from
## a chair: a rounded felt with a raised rim, the printed zones (Supply, the
## Market, your Portfolio) and the opponents' face-down hands.
##
## Positions on the felt are in design points (dp) from the felt's centre,
## x to the right and y towards you. `project` turns them into screen
## pixels: the felt is rotated TILT_DEG about its centre line and seen
## through a PERSPECTIVE_DP camera, so far things shrink and near things
## grow. Cards laid on the felt are scaled by `depth` at their spot.

## Felt size and corner radius, in dp.
const PLANE := Vector2(380, 620)
const RADIUS := 190.0
const RIM := 14.0
const TILT_DEG := 32.0
const PERSPECTIVE_DP := 900.0

## Printed zones (plane rects, top-left origin as in the design).
const ZONE_SUPPLY := Rect2(160, 132, 60, 78)
const ZONE_MARKET := Rect2(45, 218, 290, 150)
const ZONE_PORTFOLIO := Rect2(45, 372, 290, 82)
## Where the supply pile sits, from the centre.
const SUPPLY_AT := Vector2(0, -140)

## Design points to px.
var s := 1.85
## Screen position (local px) of the felt's centre.
var origin := Vector2(360, 700)
var felt_color := Companies.TABLE_BG:
	set(value):
		felt_color = value
		queue_redraw()
var edge_color := Companies.TABLE_EDGE:
	set(value):
		edge_color = value
		queue_redraw()
var supply_count := 0:
	set(value):
		supply_count = value
		queue_redraw()
## Zones pulsing because you can use them now: "supply", "market", "portfolio".
var glow := {}:
	set(value):
		glow = value
		queue_redraw()
## Opponents' hands: [{"at": Vector2 (dp), "angle": degrees, "count": int}].
var hands: Array = []:
	set(value):
		hands = value
		queue_redraw()

## Opponents' kept shares: [{"at": Vector2 (dp), "cell": float (1 = full
## size), "cols": stacks per row, "stacks": [[company, count, holds token], ...]}].
var portfolios: Array = []:
	set(value):
		portfolios = value
		queue_redraw()

var _label_font: FontVariation


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_font = FontVariation.new()
	_label_font.base_font = UiTheme.display_font()
	_label_font.spacing_glyph = 2


func _process(_delta: float) -> void:
	if not glow.is_empty():
		queue_redraw()


## Screen position (local px) of a felt point `p` (dp from the centre).
func project(p: Vector2) -> Vector2:
	var t := deg_to_rad(TILT_DEG)
	return origin + Vector2(p.x, p.y * cos(t)) * depth(p) * s


## How much larger than at the centre line a thing at `p` looks.
func depth(p: Vector2) -> float:
	var z := p.y * sin(deg_to_rad(TILT_DEG))
	return PERSPECTIVE_DP / (PERSPECTIVE_DP - z)


## Centre of a zone rect in plane coordinates, from the felt's centre.
static func zone_center(zone: Rect2) -> Vector2:
	return zone.get_center() - PLANE / 2.0


## Screen-space bounding box of a plane rect (top-left origin).
func zone_rect(zone: Rect2) -> Rect2:
	var a := project(zone.position - PLANE / 2.0)
	var b := project(zone.end - PLANE / 2.0)
	var c := project(Vector2(zone.position.x, zone.end.y) - PLANE / 2.0)
	var r := Rect2(a, Vector2.ZERO).expand(b).expand(c)
	return r


## The whole felt on screen.
func felt_rect() -> Rect2:
	return zone_rect(Rect2(Vector2.ZERO, PLANE))


## Opponent hand spots around the far half of the felt, left to right.
static func hand_spots(n: int) -> Array:
	var out := []
	for i in n:
		var a := 0.0 if n == 1 else -90.0 + 180.0 * i / (n - 1)
		var r := deg_to_rad(a)
		out.append({"at": Vector2(150.0 * sin(r), -150.0 - 112.0 * cos(r)), "angle": a + 180.0})
	return out


## Where an opponent lays the shares they keep: between their hand at
## `hand_at` and the middle of the far half, clear of the Supply.
static func portfolio_spot(hand_at: Vector2) -> Vector2:
	return hand_at + (Vector2(0, -150) - hand_at).normalized() * 66.0


## Size of an opponent's share stacks for `n` opponents, so neighbours'
## stacks do not run into each other at a full table.
static func portfolio_cell(n: int) -> float:
	return [1.1, 1.1, 1.1, 1.0, 0.8, 0.65][clampi(n, 1, 6) - 1]


## Stacks per row for opponent `i` of `n`: the seat straight across from
## you lays all six in one row, so a second row cannot reach the Supply;
## the rest use rows of three.
static func portfolio_cols(i: int, n: int) -> int:
	return 6 if n % 2 == 1 and i == n / 2 and n <= 3 else 3


func _draw() -> void:
	var outline := _stadium(Rect2(Vector2.ZERO, PLANE), RADIUS)
	var projected := PackedVector2Array()
	for p in outline:
		projected.append(project(p - PLANE / 2.0))
	# Drop shadow, two rim layers below the felt, then the felt itself.
	draw_colored_polygon(_shifted(projected, Vector2(0, 26 * s)), Color(0, 0, 0, 0.32))
	draw_colored_polygon(_shifted(projected, Vector2(0, 13 * s)), edge_color.darkened(0.42))
	draw_colored_polygon(_shifted(projected, Vector2(0, 6.5 * s)), edge_color.darkened(0.16))
	draw_colored_polygon(projected, edge_color)
	var inner := PackedVector2Array()
	for p in _stadium(Rect2(Vector2(RIM, RIM), PLANE - Vector2(RIM, RIM) * 2), RADIUS - RIM):
		inner.append(project(p - PLANE / 2.0))
	_draw_felt(inner)
	draw_polyline(_closed(inner), Color(Companies.INK, 0.35), 1.5 * s, true)
	draw_polyline(_closed(projected), Companies.INK, 2.0 * s, true)

	# Each zone's name stands on the top-left of its own outline, so a name
	# always touches the thing it names and clears the shares, which start
	# right under that line.
	# WHY not under the Portfolio as before: the hand stands there and
	# covered the words whenever a card was picked.
	var market := _legend_rect("THE MARKET", ZONE_MARKET)
	var portfolio := _legend_rect("YOUR PORTFOLIO", ZONE_PORTFOLIO)
	# The Market's bottom line runs behind the Portfolio's name: it skips it.
	_draw_zone(ZONE_MARKET, glow.has("market"), portfolio)
	_draw_zone(ZONE_SUPPLY, glow.has("supply"))
	_draw_zone(ZONE_PORTFOLIO, glow.has("portfolio"))
	_draw_legend("THE MARKET", market, glow.has("market"))
	_draw_legend("YOUR PORTFOLIO", portfolio, glow.has("portfolio"))
	_draw_supply_stack()
	for h in hands:
		_draw_hand_backs(h["at"], float(h["angle"]), int(h["count"]))
	for pf in portfolios:
		_draw_portfolio(pf["at"], pf["stacks"], float(pf["cell"]), int(pf["cols"]))


## Felt with a lighter middle: a fan of triangles from the centre.
func _draw_felt(ring: PackedVector2Array) -> void:
	var middle := project(Vector2(0, -40))
	var light := felt_color.lightened(0.18)
	var dark := felt_color.darkened(0.06)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		draw_polygon(PackedVector2Array([middle, a, b]), PackedColorArray([light, dark, dark]))


## `gap` is a screen rect the dashed line leaves free (the zone's legend).
func _draw_zone(zone: Rect2, on: bool, gap := Rect2()) -> void:
	var pts := PackedVector2Array()
	for p in _stadium(zone, 14):
		pts.append(project(p - PLANE / 2.0))
	if on:
		var pulse := 0.3 + 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * PI * 2.0))
		draw_colored_polygon(pts, Color(Companies.CARD_FACE, pulse))
		draw_polyline(_closed(pts), UiTheme.OUTLINE, 2.0 * s, true)
		return
	# Dashed print line.
	var ink := Color(_print_color(), 0.45)
	var dash := 6.0 * s
	var carry := 0.0
	var drawing := true
	var closed := _closed(pts)
	for i in closed.size() - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(dash - carry, seg - t)
			if drawing and not gap.has_point(a.lerp(b, (t + step / 2.0) / seg)):
				draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), ink, 2.0 * s)
			t += step
			carry += step
			if carry >= dash - 0.01:
				carry = 0.0
				drawing = not drawing


## Ink for words printed on the felt: the felt's own hue, darkened, so
## every felt skin gets a matching print instead of plain black.
func _print_color() -> Color:
	return Color.from_hsv(felt_color.h, clampf(felt_color.s * 2.2 + 0.12, 0.2, 0.7), 0.27)


func _legend_px(p: Vector2) -> int:
	return int(UiTheme.TYPE_CAPTION * s * depth(p))


## Screen rect of a zone's legend: standing on the zone's top line, a
## little in from its left corner.
func _legend_rect(text: String, zone: Rect2) -> Rect2:
	var p := zone.position + Vector2(10, 0) - PLANE / 2.0
	var px := _legend_px(p)
	var at := project(p)
	var w := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pad := px * 0.55
	return Rect2(at.x - pad, at.y - px * 1.5 - 2.0 * s, w + pad * 2.0, px * 1.5)


## A zone's name: printed in the felt's dark tone, or, while the zone can be
## used (`on`), gold letters on an ink tab.
func _draw_legend(text: String, rect: Rect2, on: bool) -> void:
	var px := int(rect.size.y / 1.5)
	var base := Vector2(rect.position.x + px * 0.55, rect.get_center().y + px * 0.36)
	if on:
		draw_style_box(UiTheme.ink_box(UiTheme.OUTLINE, rect.size.y / 2.0, 0), rect)
	draw_string(_label_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.GOLD if on else _print_color())


## How many shares are left to draw, on an ink tab across the foot of the
## pile it counts. `canvas` is a node above the pile, at the board's origin.
## WHY not on the Market's line as before: there it read as a second name
## for the Market.
func draw_supply_count(canvas: CanvasItem) -> void:
	var half := 0.48 * 140.0 / 2.0
	var p := SUPPLY_AT + Vector2(0, half - 2.0)
	var px := _legend_px(p)
	var word := "SUPPLY"
	var count := str(supply_count)
	var count_font := UiTheme.display_font()
	var word_w := _label_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var count_w := count_font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var gap := px * 0.45
	var pad := px * 0.7
	var c := project(p)
	var rect := Rect2(c.x - (word_w + gap + count_w) / 2.0 - pad, c.y - px * 0.75, word_w + gap + count_w + pad * 2.0, px * 1.5)
	canvas.draw_style_box(UiTheme.ink_box(UiTheme.OUTLINE, rect.size.y / 2.0, 0), rect)
	var base := Vector2(rect.position.x + pad, rect.get_center().y + px * 0.36)
	canvas.draw_string(_label_font, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.TEXT)
	canvas.draw_string(count_font, base + Vector2(word_w + gap, 0), count, HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.GOLD)


## Edges of the face-down supply under its top card.
func _draw_supply_stack() -> void:
	if supply_count <= 1:
		return
	var c := project(SUPPLY_AT)
	var k := 0.48 * depth(SUPPLY_AT) * s
	var size_px := Vector2(100, 140) * k
	var layers := mini(8, supply_count / 3 + 1)
	for i in layers:
		var r := Rect2(c - size_px / 2.0 + Vector2(0, (layers - i) * 1.6 * s), size_px)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Companies.CARD_FACE
		sb.border_color = Companies.INK
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(5 * s))
		draw_style_box(sb, r)


## A small fan of card backs, rotated to face the seat they belong to.
func _draw_hand_backs(at: Vector2, angle: float, count: int) -> void:
	var c := project(at)
	var k := 0.42 * depth(at) * s
	var card := Vector2(100, 140) * k
	for i in count:
		var off := i - (count - 1) / 2.0
		var rot := deg_to_rad(angle + off * 9.0)
		var spot := c + Vector2(off * 20.0 * k, off * off * 2.5 * k).rotated(deg_to_rad(angle))
		draw_set_transform(spot, rot, Vector2(1.0, 0.8))
		var r := Rect2(-card / 2.0, card)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Companies.CARD_FACE
		sb.border_color = Companies.INK
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(6 * k))
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = int(4 * s)
		sb.shadow_offset = Vector2(0, 3 * s)
		draw_style_box(sb, r)
		var stripe := (card.x - 10 * k) / 6.0
		for j in 6:
			draw_rect(Rect2(r.position.x + 5 * k + j * stripe, r.position.y + 6 * k, stripe - 2 * k, 10 * k), Companies.color_of(j))
			draw_rect(Rect2(r.position.x + 5 * k + j * stripe, r.end.y - 16 * k, stripe - 2 * k, 10 * k), Companies.color_of(j))
		draw_line(Vector2(r.position.x + 10 * k, 0), Vector2(r.end.x - 10 * k, 0), Companies.INK, maxf(1.0, 3 * k))
	draw_set_transform(Vector2.ZERO)


## An opponent's kept shares: a small face-up stack per company, `cols` to
## a row, with the count on top and a regulator chip on the corner of each
## company they hold the token for.
func _draw_portfolio(at: Vector2, stacks: Array, cell: float, cols: int) -> void:
	if stacks.is_empty():
		return
	var display := UiTheme.display_font()
	var n := stacks.size()
	var rows := ceili(n / float(cols))
	var step := Vector2(23.0, 29.0) * cell
	var chips := []
	for i in n:
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var p := at + Vector2((i % cols - (in_row - 1) / 2.0) * step.x, (row - (rows - 1) / 2.0) * step.y)
		var k := depth(p) * s
		var c := project(p)
		var card := Vector2(20.0, 26.0) * cell * k
		var company: int = stacks[i][0]
		var count: int = stacks[i][1]
		# Edges of the shares under the top one, then the top one.
		for e in range(mini(count, 3) - 1, -1, -1):
			var r := Rect2(c - card / 2.0 + Vector2(0, e * 1.8 * k), card)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Companies.color_of(company).darkened(0.25 if e > 0 else 0.0)
			sb.border_color = Companies.INK
			sb.set_border_width_all(maxi(1, int(1.2 * k)))
			sb.set_corner_radius_all(int(3 * k))
			if e == mini(count, 3) - 1:
				sb.shadow_color = Color(0, 0, 0, 0.25)
				sb.shadow_size = int(2 * s)
				sb.shadow_offset = Vector2(0, 1.5 * s)
			draw_style_box(sb, r)
		var txt := str(count)
		var px := int(14.0 * cell * k)
		var tw := display.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(display, c + Vector2(-tw / 2.0, px * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.band_text_color(company))
		if stacks[i][2]:
			chips.append([c + Vector2(card.x / 2.0 - 1.0 * k, -card.y / 2.0 + 1.0 * k), 10.0 * maxf(cell, 0.9) * k, company])
	# WHY: chips go on after every stack so a neighbouring stack cannot
	# cover one.
	for chip in chips:
		draw_chip(self, chip[0], chip[1], chip[2])


## A regulator (monopoly) chip: a gold poker chip edged in the company's
## colour with an "R", centred on `c` with radius `r` px.
static func draw_chip(ci: CanvasItem, c: Vector2, r: float, company: int) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.22), r, Color(0, 0, 0, 0.3))
	ci.draw_circle(c, r, Companies.INK)
	ci.draw_circle(c, r * 0.86, Companies.GOLD)
	for i in 6:
		var a := TAU * i / 6.0
		ci.draw_arc(c, r * 0.71, a - 0.24, a + 0.24, 6, Companies.color_of(company), r * 0.3)
	ci.draw_arc(c, r * 0.5, 0, TAU, 24, Companies.INK, maxf(1.0, r * 0.1), true)
	var display := UiTheme.display_font()
	var px := int(r * 0.95)
	var rw := display.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_string(display, c + Vector2(-rw / 2.0, px * 0.36), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)


## Outline of a rounded rect, in plane coordinates (top-left origin).
func _stadium(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI / 2.0],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI / 2.0],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	var steps := 14
	for corner in corners:
		for i in steps + 1:
			var a: float = corner[1] + PI / 2.0 * i / steps
			pts.append(corner[0] + Vector2(cos(a), sin(a)) * r)
	return pts


static func _shifted(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
