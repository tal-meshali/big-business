"""Writes the brand artwork as SVG, in the "After-hours trading floor" look
(docs/design/theme.md): the lobby's royal purple room with gold rays, three
share cards fanned with ink outlines, a glossy gold capital coin, and on the
splash the gold BIG BUSINESS wordmark.

Outputs:
    client/icon.svg                     app icon (also the project icon)
    tools/art/android_background.svg    adaptive icon background (room only)
    tools/art/android_foreground.svg    adaptive icon foreground (cards, coin)
    tools/art/splash.svg                portrait boot splash, 1080x1920

Text is converted to outlines with the game's own Archivo Black, so the SVGs
need no fonts and Godot's SVG loader renders them exactly.

Run from anywhere, then rasterise with tools/make_icons.gd:
    pip install fonttools uharfbuzz skia-pathops
    python3 tools/logo_art.py
    godot --headless --path client -s ../tools/make_icons.gd
"""

import math
import os
from collections import namedtuple

import pathops
import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_PATH = os.path.join(ROOT, "client", "fonts", "archivo_black.ttf")

# Game palette: client/scripts/ui/ui_theme.gd and client/scripts/game/companies.gd.
NIGHT = "#120C2E"
ROYAL = "#2B1D73"
ROYAL_GLOW = "#4C34C9"
INK = "#1A1238"
FACE = "#FFFDF6"
GOLD = "#FFC83D"
GOLD_PALE = "#FFF0A0"
GOLD_DEEP = "#F09A00"
PINE = "#3F9E4F"
FREIGHT = "#2E6FD8"
MOTORS = "#D6262C"

# Art-only colours, from client/scripts/ui/lobby_backdrop.gd, logo_title.gd
# and the direction mockup (/mnt/project-files/design/visual-direction.html).
RAY = "#FFD66E"  # LobbyBackdrop's rays, Color(1, 0.84, 0.43)
EXTRUDE = "#5A2600"  # LogoTitle's extrusion
SHADOW = "#07041A"  # drop shadows on the purple room
COIN_LIGHT = "#FFF1B0"  # mockup .coin: #FFF1B0, #FFC83D 45%, #C77A00
COIN_DARK = "#C77A00"
COIN_EDGE = "#6B3A00"
COIN_MARK = "#6B2A00"  # struck into the coin, mockup's logo brown

# Archivo Black's cap height, in em.
CAP = 0.686
# WHY not the TTF's 0.878: LogoTitle lays its lines out with
# UiTheme.display_font().get_ascent(), and that font's fallbacks (emoji,
# Nunito) raise the reported ascent to 1.07 em. Measured in Godot 4.6.
LOGO_ASCENT = 1.07

_font = TTFont(FONT_PATH)
_glyphs = _font.getGlyphSet()
_upem = _font["head"].unitsPerEm
with open(FONT_PATH, "rb") as fh:
    _hb_font = hb.Font(hb.Face(fh.read()))


def text_path(text, x, baseline, size, anchor="middle", solid=False):
    """SVG path data for `text` in Archivo Black at `size` px, kerned, with
    `anchor` "start", "middle" or "end" at `x`. The outlines go through
    skia-pathops so overlapping contours can't punch holes. `solid` drops the
    counters, for layers that sit behind the face (outline, extrusion)."""
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(_hb_font, buf, {"kern": True, "liga": False})
    k = size / _upem
    width = sum(p.x_advance for p in buf.glyph_positions) * k
    pen_x = x - {"start": 0.0, "middle": width / 2.0, "end": width}[anchor]
    path = pathops.Path()
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = _font.getGlyphName(info.codepoint)
        tp = TransformPen(path.getPen(), (k, 0, 0, -k, pen_x + pos.x_offset * k, baseline - pos.y_offset * k))
        _glyphs[name].draw(tp)
        pen_x += pos.x_advance * k
    path.simplify(fix_winding=True)
    if solid:
        contours = list(path.contours)
        outer = max(contours, key=lambda c: abs(c.area)).clockwise
        kept = pathops.Path()
        for c in contours:
            if c.clockwise == outer:
                kept.addPath(c)
        path = kept
    pen = SVGPathPen(None, ntos=lambda v: ("%.2f" % v).rstrip("0").rstrip("."))
    path.draw(pen)
    return pen.getCommands()


def outlined_text(text, x, baseline, size, stroke_w, anchor="start"):
    """A white number with an ink outline, like the card numbers in the game:
    the ink stroke first, the white face on top, so the outline only shows
    outside the glyph and the band colour shows through the counters."""
    d = text_path(text, x, baseline, size, anchor)
    return (
        f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{stroke_w:.1f}" stroke-linejoin="round"/>'
        f'<path d="{d}" fill="#FFFFFF"/>'
    )


# ---------------------------------------------------------------- background


def room(w, h, cx, cy, rx, ry, ray_len, phase, ray_stops):
    """The lobby's room (LobbyBackdrop): a glow from ROYAL_GLOW through ROYAL
    to NIGHT around (cx, cy), radii rx by ry, and sixteen gold rays, each
    64% of its slice wide (LobbyBackdrop's half-angle is 0.32 of a slice),
    the first at `phase` radians, fading out over `ray_len` through
    `ray_stops`, a list of (offset, opacity)."""
    cx, cy = round(cx, 1), round(cy, 1)
    stops = "\n".join(f'      <stop offset="{o}" stop-color="{RAY}" stop-opacity="{a}"/>' for o, a in ray_stops)
    out = [f"""
  <defs>
    <radialGradient id="room" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{rx}"
        gradientTransform="translate({cx} {cy}) scale(1 {ry / rx:.4f}) translate({-cx} {-cy})">
      <stop offset="0" stop-color="{ROYAL_GLOW}"/>
      <stop offset="0.45" stop-color="{ROYAL}"/>
      <stop offset="1" stop-color="{NIGHT}"/>
    </radialGradient>
    <radialGradient id="rayfade" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{ray_len:.0f}">
{stops}
    </radialGradient>
  </defs>
  <rect width="{w}" height="{h}" fill="url(#room)"/>"""]
    count = 16
    half = math.pi * 2.0 / count * 0.32
    wedges = []
    for i in range(count):
        a = phase + i * 2.0 * math.pi / count
        p1 = (cx + math.cos(a - half) * ray_len, cy + math.sin(a - half) * ray_len)
        p2 = (cx + math.cos(a + half) * ray_len, cy + math.sin(a + half) * ray_len)
        wedges.append(f"M{cx} {cy} L{p1[0]:.1f} {p1[1]:.1f} L{p2[0]:.1f} {p2[1]:.1f}Z")
    out.append(f'  <path d="{" ".join(wedges)}" fill="url(#rayfade)"/>')
    return "\n".join(out)


def sparkle(x, y, r):
    """A four-point gold glint, like the lobby's sparkles."""
    t = r * 0.22
    d = (
        f"M{x} {y - r} Q{x + t} {y - t} {x + r} {y} Q{x + t} {y + t} {x} {y + r} "
        f"Q{x - t} {y + t} {x - r} {y} Q{x - t} {y - t} {x} {y - r}Z"
    )
    return f'<path d="{d}" fill="{GOLD_PALE}"/>'


# -------------------------------------------------------------------- cards

CARD_W, CARD_H, CARD_R = 300, 420, 34
BAND_H = 118
OUTLINE_W = 22  # ink weight for the icon: ~1.3 px at 60 px


def _mix(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join("%02X" % round(x + (y - x) * t) for x, y in zip(ca, cb))


def company_icon(kind, cx, cy, box, color):
    """The company art in a 24-unit box. Keep in sync with card_view.gd's
    _draw_icon (same shapes; heavier strokes so they survive icon sizes)."""
    k = box / 24.0
    w = 2.1 * k

    def P(x, y):
        return f"{cx + (x - 12) * k:.1f} {cy + (y - 12) * k:.1f}"

    def R(v):
        return f"{v * k:.1f}"

    line = f'stroke="{INK}" stroke-width="{w:.1f}" stroke-linecap="round" stroke-linejoin="round"'
    if kind == "pine":
        tri = f"M{P(12, 2)} L{P(19, 21)} L{P(5, 21)}Z"
        d = f"M{P(8.6, 12)} L{P(15.4, 12)} M{P(7, 16.5)} L{P(17, 16.5)} M{P(12, 7)} L{P(12, 21)}"
        return f'<path d="{tri}" fill="{color}" {line}/><path d="{d}" fill="none" {line}/>'
    if kind == "anchor":
        cx5, cy5 = P(12, 5).split()
        return (f'<circle cx="{cx5}" cy="{cy5}" r="{R(2.3)}" fill="{color}" {line}/>'
                f'<path d="M{P(12, 7.3)} L{P(12, 21)} M{P(8, 10.5)} L{P(16, 10.5)} '
                f'M{P(4.5, 13.5)} A{R(7.5)} {R(7.5)} 0 0 0 {P(19.5, 13.5)}" fill="none" {line}/>')
    if kind == "wheel":
        c12x, c12y = P(12, 12).split()
        bolt = [[13.2, 7.2], [9.4, 12.6], [12.5, 12.6], [11.4, 16.8], [15.2, 11.3], [12.1, 11.3]]
        bd = "M" + " L".join(P(x, y) for x, y in bolt) + "Z"
        return (f'<circle cx="{c12x}" cy="{c12y}" r="{R(9.5)}" fill="{color}" {line}/>'
                f'<circle cx="{c12x}" cy="{c12y}" r="{R(6.2)}" fill="{FACE}" {line}/>'
                f'<path d="{bd}" fill="{INK}" stroke="{INK}" stroke-width="{w * 0.4:.1f}" stroke-linejoin="round"/>')
    raise ValueError(kind)


def card(uid, x, y, angle, pivot, color, number, icon, number_side="start", art_shift=0.0, sheen=False):
    """One share card, top-left at (x, y), turned `angle` degrees around
    `pivot`. Title-deed layout from the game: colour band with the share
    count, art window. `number_side` "end" puts the count at the band's right
    end, for a card whose left end is covered; `art_shift` slides the art
    sideways so it stays in the uncovered part of the window."""
    w, h, r = CARD_W, CARD_H, CARD_R
    band = (f"M{x} {y + r} A{r} {r} 0 0 1 {x + r} {y} H{x + w - r} "
            f"A{r} {r} 0 0 1 {x + w} {y + r} V{y + BAND_H} H{x}Z")
    win_x, win_y, win_w, win_h = x + 30, y + BAND_H + 30, w - 60, h - BAND_H - 80
    tint = _mix(FACE, color, 0.2)
    num_x = x + 30 if number_side == "start" else x + w - 30
    gloss = ""
    if sheen:
        streak = (f"M{x - 40} {y + h * 0.62} L{x + w * 0.62} {y - 40} L{x + w * 0.62 + 70} {y - 40} "
                  f"L{x + 30} {y + h * 0.62 + 70}Z")
        gloss = (f'<clipPath id="clip{uid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>'
                 f'<g clip-path="url(#clip{uid})"><path d="{streak}" fill="#FFFFFF" opacity="0.22"/></g>')
    rot = f"rotate({angle} {pivot[0]} {pivot[1]})"
    # WHY the shadow sits outside the rotation: one light, straight above.
    return f"""
  <g transform="translate(0 18)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" transform="{rot}" fill="{SHADOW}" opacity="0.5"/></g>
  <g transform="{rot}">
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{FACE}"/>
    <path d="{band}" fill="{color}"/>
    <rect x="{x}" y="{y + BAND_H - 22}" width="{w}" height="22" fill="#000000" opacity="0.12"/>
    <line x1="{x}" y1="{y + BAND_H}" x2="{x + w}" y2="{y + BAND_H}" stroke="{INK}" stroke-width="16"/>
    <rect x="{win_x}" y="{win_y}" width="{win_w}" height="{win_h}" rx="18" fill="{tint}" stroke="{INK}" stroke-width="10"/>
    {company_icon(icon, win_x + win_w / 2 + art_shift, win_y + win_h / 2, 184, color)}
    {gloss}
    {outlined_text(str(number), num_x, y + 96, 92, 18, anchor=number_side)}
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="none" stroke="{INK}" stroke-width="{OUTLINE_W}"/>
  </g>"""


# --------------------------------------------------------------------- coin


def coin(cx, cy, r):
    """The gold capital coin, glossy like the mockup's coin, with a rising
    arrow struck into it."""
    inner = r * 0.8
    s = r / 150.0

    def p(x, y):
        return f"{cx + x * s:.1f} {cy + y * s:.1f}"

    arrow = f"M{p(-70, 42)} L{p(-22, -6)} L{p(10, 24)} L{p(58, -26)}"
    head = f"M{p(82, -52)} L{p(78, 8)} L{p(22, -48)}Z"
    stroke = f'stroke-width="{38 * s:.1f}" stroke-linecap="round" stroke-linejoin="round"'
    return f"""
  <defs>
    <radialGradient id="coinface" cx="0.35" cy="0.3" r="0.75">
      <stop offset="0" stop-color="{COIN_LIGHT}"/>
      <stop offset="0.45" stop-color="{GOLD}"/>
      <stop offset="1" stop-color="{COIN_DARK}"/>
    </radialGradient>
    <linearGradient id="coinrim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{COIN_LIGHT}"/>
      <stop offset="0.5" stop-color="{GOLD_DEEP}"/>
      <stop offset="1" stop-color="{COIN_EDGE}"/>
    </linearGradient>
  </defs>
  <circle cx="{cx}" cy="{cy + r * 0.13:.1f}" r="{r}" fill="{SHADOW}" opacity="0.5"/>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#coinrim)" stroke="{INK}" stroke-width="{OUTLINE_W * s:.1f}"/>
  <circle cx="{cx}" cy="{cy}" r="{inner:.1f}" fill="url(#coinface)" stroke="{COIN_DARK}" stroke-width="{7 * s:.1f}"/>
  <g transform="translate(0 {5 * s:.1f})">
    <path d="{arrow}" fill="none" stroke="{COIN_LIGHT}" {stroke}/>
    <path d="{head}" fill="{COIN_LIGHT}" stroke="{COIN_LIGHT}" stroke-width="{12 * s:.1f}" stroke-linejoin="round"/>
  </g>
  <path d="{arrow}" fill="none" stroke="{COIN_MARK}" {stroke}/>
  <path d="{head}" fill="{COIN_MARK}" stroke="{COIN_MARK}" stroke-width="{12 * s:.1f}" stroke-linejoin="round"/>
  <path d="M{p(-112, -26)} A{inner:.1f} {inner:.1f} 0 0 1 {p(-26, -112)}" fill="none" stroke="#FFFFFF" stroke-width="{14 * s:.1f}" stroke-linecap="round" opacity="0.75"/>"""


# ---------------------------------------------------------------- the scene


def hero(cx, cy, scale):
    """The fanned cards and the coin, drawn in a 1024 box whose centre lands
    on (cx, cy), scaled by `scale`. The middle card sits on top so the hand
    and the coin read as one subject."""
    pivot = (512, 940)
    body = (
        card("L", 362, 190, -26, pivot, PINE, 6, "pine", art_shift=-34)
        + card("R", 362, 190, 26, pivot, FREIGHT, 7, "anchor", number_side="end", art_shift=34)
        + card("C", 362, 160, 0, pivot, MOTORS, 10, "wheel", sheen=True)
        + coin(512, 700, 150)
    )
    return f'<g transform="translate({cx} {cy}) scale({scale}) translate(-512 -512)">{body}\n</g>'


Line = namedtuple("Line", "face solid size baseline")


def wordmark(cx, top, px):
    """BIG over BUSINESS laid out and drawn the way LogoTitle draws it, so the
    splash hands over to the lobby without a jump: a soft shadow, a brown
    extrusion, the ink outline, and a toon-shaded gold face (pale top band,
    gold middle, deep gold bottom), tilted -3 degrees. `px` is LogoTitle.px.
    `top` is the top of LogoTitle's box, as in its _line_rect.
    WHY the ink stroke is a third of LogoTitle's outline size: measured
    against the lobby, Godot's font outline shows about a sixth of its size
    outside the glyph."""
    outline = px * 0.17 / 3.0
    depth = px * 0.1
    y = top + px * 0.02
    lines = []
    for text, sz in (("BIG", px * 0.7), ("BUSINESS", px)):
        baseline = y + sz * LOGO_ASCENT
        lines.append(Line(text_path(text, cx, baseline, sz), text_path(text, cx, baseline, sz, solid=True), sz, baseline))
        y = baseline + px * 0.06
    # LogoTitle's bands, from the top of the ascent: pale down to 40%, gold
    # down to 74%, deep gold below. Here as offsets over the cap height.
    pale_end = (LOGO_ASCENT * 0.4 - (LOGO_ASCENT - CAP)) / CAP
    gold_end = (LOGO_ASCENT * 0.74 - (LOGO_ASCENT - CAP)) / CAP
    out = ["<defs>"]
    for i, ln in enumerate(lines):
        out.append(
            f'<linearGradient id="goldface{i}" gradientUnits="userSpaceOnUse" x1="0" y1="{ln.baseline - ln.size * CAP:.1f}" x2="0" y2="{ln.baseline:.1f}">'
            f'<stop offset="{pale_end:.3f}" stop-color="{GOLD_PALE}"/><stop offset="{pale_end:.3f}" stop-color="{GOLD}"/>'
            f'<stop offset="{gold_end:.3f}" stop-color="{GOLD}"/><stop offset="{gold_end:.3f}" stop-color="{GOLD_DEEP}"/>'
            f'</linearGradient>')
    out.append("</defs>")
    mid = (top + y) / 2.0
    out.append(f'<g transform="rotate(-3 {cx} {mid:.1f})">')
    stroke = f'stroke-width="{outline:.1f}" stroke-linejoin="round"'
    for ln in lines:
        out.append(f'<path d="{ln.solid}" transform="translate(0 {depth + px * 0.06:.1f})" fill="#000000" '
                   f'stroke="#000000" opacity="0.3" {stroke}/>')
    steps = max(1, int(depth))  # LogoTitle: one copy per pixel of depth
    for ln in lines:
        for k in range(steps, 0, -1):
            out.append(f'<path d="{ln.solid}" transform="translate(0 {depth * k / steps:.1f})" fill="{EXTRUDE}" '
                       f'stroke="{EXTRUDE}" {stroke}/>')
    for ln in lines:
        out.append(f'<path d="{ln.solid}" fill="{INK}" stroke="{INK}" {stroke}/>')
    for i, ln in enumerate(lines):
        out.append(f'<path d="{ln.face}" fill="url(#goldface{i})"/>')
    out.append("</g>")
    return "\n  ".join(out)


def _svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            f"  <!-- Generated by tools/logo_art.py; edit that, not this file. -->{body}\n</svg>\n")


# The icon's rays are a touch brighter near the centre than the lobby's and
# leave a gap pointing straight up, so the centre card stands in shadow-free
# light.
ICON_ROOM = dict(w=1024, h=1024, cx=512, cy=430, rx=760, ry=760, ray_len=900,
                 phase=-math.pi / 2.0 + math.pi / 16.0, ray_stops=[(0, 0.3), (0.45, 0.1), (1, 0)])


def icon_svg():
    return _svg(1024, 1024, room(**ICON_ROOM) + sparkle(160, 200, 40) + sparkle(872, 168, 30) + hero(512, 500, 1.0))


def android_background_svg():
    # Only the room: Android shows the middle 72/108 of this layer and masks
    # it to the launcher's shape, which would cut sparkles in half.
    return _svg(1024, 1024, room(**ICON_ROOM))


def android_foreground_svg():
    # 0.62 keeps the art (shadows included) inside the 66 dp safe circle of the 108 dp layer.
    return _svg(1024, 1024, hero(512, 512, 0.62))


SPLASH_W, SPLASH_H = 1080, 1920


def splash_svg():
    """Portrait splash, shown with stretch mode Cover. The room is the
    lobby's exactly as its first frame draws it (rays centred at 26% of the
    height, a ray pointing right, the same fade) and the wordmark has
    LogoTitle's size and place in the lobby (BIG's top at 53.7% of the
    height, measured at 720x1560), so at the cut the room and the wordmark
    stay put and only the hand changes. Content stays inside x 120..960 and
    y 260..1660, which survives Cover's crop from tall 19.5:9 phones to 3:4
    tablets; on a tablet the crop moves everything up about 8% of the
    height, which is fine for a splash."""
    w, h = SPLASH_W, SPLASH_H
    px = 92
    top = h * 0.537 - px * (0.02 + (LOGO_ASCENT - CAP) * 0.7)
    body = (room(w, h, w / 2, h * 0.26, w * 0.8, h * 0.8, math.hypot(w, h), 0.0, [(0, 0.22), (1, 0)])
            + sparkle(220, 330, 30) + sparkle(880, 300, 22)
            + hero(w / 2, h * 0.33, 0.72)
            + wordmark(w / 2, top, px))
    return _svg(w, h, body)


def main():
    art = os.path.join(ROOT, "tools", "art")
    os.makedirs(art, exist_ok=True)
    outputs = {
        os.path.join(ROOT, "client", "icon.svg"): icon_svg(),
        os.path.join(art, "android_background.svg"): android_background_svg(),
        os.path.join(art, "android_foreground.svg"): android_foreground_svg(),
        os.path.join(art, "splash.svg"): splash_svg(),
    }
    for path, svg in outputs.items():
        with open(path, "w") as fh:
            fh.write(svg)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
