"""Writes the brand artwork as SVG: the app icon (client/icon.svg) and the
boot splash (tools/art/splash.svg), in the "After-hours trading floor" look
(docs/design/theme.md): royal purple glow with gold rays, three share cards
fanned with ink outlines, a glossy gold capital coin, and on the splash the
gold BIG BUSINESS wordmark.

Text is converted to outlines with the game's own Archivo Black, so the SVGs
need no fonts and Godot's SVG loader renders them exactly.

Run from the repo root, then rasterise with tools/make_icons.gd:
    pip install fonttools uharfbuzz
    python3 tools/logo_art.py
    godot --headless --path client -s ../tools/make_icons.gd
"""

import math
import os

import pathops
import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_PATH = os.path.join(ROOT, "client", "fonts", "archivo_black.ttf")

# Palette, from client/scripts/ui/ui_theme.gd and companies.gd.
NIGHT = "#120C2E"
ROYAL = "#2B1D73"
ROYAL_GLOW = "#4C34C9"
INK = "#1A1238"
FACE = "#FFFDF6"
GOLD = "#FFC83D"
GOLD_PALE = "#FFF0A0"
GOLD_DEEP = "#F09A00"
EXTRUDE = "#5A2600"  # LogoTitle's extrusion
PINE = "#3F9E4F"
FREIGHT = "#2E6FD8"
MOTORS = "#D6262C"

_font = TTFont(FONT_PATH)
_glyphs = _font.getGlyphSet()
_upem = _font["head"].unitsPerEm
with open(FONT_PATH, "rb") as fh:
    _hb_font = hb.Font(hb.Face(fh.read()))


def text_path(text, x, baseline, size, anchor="middle", tracking=0.0, solid=False):
    """SVG path data for `text` in Archivo Black, `size` px, kerned.
    The outlines are cleaned with skia-pathops (the font has a few tiny
    self-crossing loops that render as specks). `solid` drops the counters,
    for layers that sit behind the face (outline, extrusion, shadow).
    Returns (d, width)."""
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(_hb_font, buf, {"kern": True, "liga": False})
    k = size / _upem
    names = [_font.getGlyphName(i.codepoint) for i in buf.glyph_infos]
    advances = [p.x_advance * k + size * tracking for p in buf.glyph_positions]
    width = sum(advances) - size * tracking
    start = x - (width / 2.0 if anchor == "middle" else 0.0)
    path = pathops.Path()
    pen_x = start
    for name, adv, pos in zip(names, advances, buf.glyph_positions):
        tp = TransformPen(path.getPen(), (k, 0, 0, -k, pen_x + pos.x_offset * k, baseline - pos.y_offset * k))
        _glyphs[name].draw(tp)
        pen_x += adv
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
    return pen.getCommands(), width


def outlined_text(text, x, baseline, size, fill, stroke=INK, stroke_w=None, anchor="middle"):
    """White-on-ink numbers like the game's labels: the ink stroke first,
    then the fill on top, so the stroke only grows outwards."""
    d, _ = text_path(text, x, baseline, size, anchor)
    solid, _ = text_path(text, x, baseline, size, anchor, solid=True)
    sw = stroke_w if stroke_w is not None else size * 0.16
    return (
        f'<path d="{solid}" fill="{stroke}" stroke="{stroke}" stroke-width="{sw:.1f}" stroke-linejoin="round"/>'
        f'<path d="{d}" fill="{fill}"/>'
    )


# ---------------------------------------------------------------- background


def defs_background(cx, cy, r):
    return f"""
    <radialGradient id="room" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">
      <stop offset="0" stop-color="#5B41E0"/>
      <stop offset="0.22" stop-color="{ROYAL_GLOW}"/>
      <stop offset="0.6" stop-color="{ROYAL}"/>
      <stop offset="1" stop-color="{NIGHT}"/>
    </radialGradient>
    <radialGradient id="rayfade" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r * 0.95:.0f}">
      <stop offset="0" stop-color="{GOLD}" stop-opacity="0.42"/>
      <stop offset="0.5" stop-color="{GOLD}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="{GOLD}" stop-opacity="0"/>
    </radialGradient>"""


def rays(cx, cy, length, count=16, offset_deg=0.0):
    """`count` gold wedges turning out of (cx, cy), like LobbyBackdrop."""
    out = []
    half = math.pi / count / 2.0
    for i in range(count):
        a = math.radians(offset_deg) + i * 2.0 * math.pi / count
        p1 = (cx + math.cos(a - half) * length, cy + math.sin(a - half) * length)
        p2 = (cx + math.cos(a + half) * length, cy + math.sin(a + half) * length)
        out.append(f"M{cx} {cy} L{p1[0]:.1f} {p1[1]:.1f} L{p2[0]:.1f} {p2[1]:.1f}Z")
    return f'<path d="{" ".join(out)}" fill="url(#rayfade)"/>'


def sparkle(x, y, r, opacity=1.0):
    """A four-point glint."""
    t = r * 0.22
    d = (
        f"M{x} {y - r} Q{x + t} {y - t} {x + r} {y} Q{x + t} {y + t} {x} {y + r} "
        f"Q{x - t} {y + t} {x - r} {y} Q{x - t} {y - t} {x} {y - r}Z"
    )
    return f'<path d="{d}" fill="#FFF6C2" opacity="{opacity}"/>'


# -------------------------------------------------------------------- cards

CARD_W, CARD_H, CARD_R = 300, 420, 34
BAND_H = 118


def _mix(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join("%02X" % round(x + (y - x) * t) for x, y in zip(ca, cb))


def company_icon(kind, cx, cy, box, color):
    """The company art from card_view.gd's _draw_icon, in a 24-unit box."""
    k = box / 24.0
    w = 1.7 * k

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
        c5 = P(12, 5).split()
        return (f'<circle cx="{c5[0]}" cy="{c5[1]}" r="{R(2.3)}" fill="{color}" {line}/>'
                f'<path d="M{P(12, 7.3)} L{P(12, 21)} M{P(8, 10.5)} L{P(16, 10.5)} '
                f'M{P(4.5, 13.5)} A{R(7.5)} {R(7.5)} 0 0 0 {P(19.5, 13.5)}" fill="none" {line}/>')
    if kind == "wheel":
        c = P(12, 12).split()
        bolt = [[13.2, 7.2], [9.4, 12.6], [12.5, 12.6], [11.4, 16.8], [15.2, 11.3], [12.1, 11.3]]
        bd = "M" + " L".join(P(x, y) for x, y in bolt) + "Z"
        return (f'<circle cx="{c[0]}" cy="{c[1]}" r="{R(9.5)}" fill="{color}" {line}/>'
                f'<circle cx="{c[0]}" cy="{c[1]}" r="{R(6.2)}" fill="{FACE}" {line}/>'
                f'<path d="{bd}" fill="{INK}" stroke="{INK}" stroke-width="{w * 0.4:.1f}" stroke-linejoin="round"/>')
    raise ValueError(kind)


def card(uid, x, y, angle, pivot, color, number, icon, number_fill="#FFFFFF"):
    """One share card, top-left at (x, y), turned `angle` degrees around
    `pivot`. Title-deed layout from the game: colour band with the share
    count, art window, glossy sheen."""
    w, h, r = CARD_W, CARD_H, CARD_R
    band = (f"M{x} {y + r} A{r} {r} 0 0 1 {x + r} {y} H{x + w - r} "
            f"A{r} {r} 0 0 1 {x + w} {y + r} V{y + BAND_H} H{x}Z")
    win_x, win_y, win_w, win_h = x + 30, y + BAND_H + 30, w - 60, h - BAND_H - 62
    tint = _mix(FACE, color, 0.2)
    sheen = (f"M{x - 40} {y + h * 0.62} L{x + w * 0.62} {y - 40} L{x + w * 0.62 + 70} {y - 40} "
             f"L{x + 30} {y + h * 0.62 + 70}Z")
    return f"""
  <g transform="rotate({angle} {pivot[0]} {pivot[1]})">
    <clipPath id="clip{uid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>
    <rect x="{x}" y="{y + 18}" width="{w}" height="{h}" rx="{r}" fill="#07041A" opacity="0.5"/>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{FACE}"/>
    <path d="{band}" fill="{color}"/>
    <rect x="{x}" y="{y + BAND_H - 22}" width="{w}" height="22" fill="#000000" opacity="0.12"/>
    <line x1="{x}" y1="{y + BAND_H}" x2="{x + w}" y2="{y + BAND_H}" stroke="{INK}" stroke-width="12"/>
    <rect x="{win_x}" y="{win_y}" width="{win_w}" height="{win_h}" rx="18" fill="{tint}" stroke="{INK}" stroke-width="8"/>
    {company_icon(icon, win_x + win_w / 2, win_y + win_h / 2, 150, color)}
    {outlined_text(str(number), x + 30, y + 96, 92, number_fill, anchor="start", stroke_w=16)}
    <g clip-path="url(#clip{uid})"><path d="{sheen}" fill="#FFFFFF" opacity="0.22"/></g>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="none" stroke="{INK}" stroke-width="16"/>
  </g>"""


# --------------------------------------------------------------------- coin


def defs_coin():
    return """
    <radialGradient id="coinface" cx="0.36" cy="0.3" r="0.8">
      <stop offset="0" stop-color="#FFF6C2"/>
      <stop offset="0.38" stop-color="#FFD24A"/>
      <stop offset="0.8" stop-color="#F0A000"/>
      <stop offset="1" stop-color="#D88400"/>
    </radialGradient>
    <linearGradient id="coinrim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFE27A"/>
      <stop offset="0.5" stop-color="#E69500"/>
      <stop offset="1" stop-color="#A85A00"/>
    </linearGradient>"""


def coin(cx, cy, r):
    """The gold capital coin, glossy, with a rising arrow struck into it."""
    inner = r * 0.8
    s = r / 150.0

    def p(x, y):
        return f"{cx + x * s:.1f} {cy + y * s:.1f}"

    arrow = f"M{p(-70, 42)} L{p(-22, -6)} L{p(10, 24)} L{p(62, -30)}"
    head = f"M{p(80, -50)} L{p(76, 4)} L{p(26, -46)}Z"
    return f"""
  <g>
    <ellipse cx="{cx}" cy="{cy + r * 0.13:.1f}" rx="{r}" ry="{r}" fill="#07041A" opacity="0.5"/>
    <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#coinrim)" stroke="{INK}" stroke-width="{16 * s:.1f}"/>
    <circle cx="{cx}" cy="{cy}" r="{inner:.1f}" fill="url(#coinface)" stroke="#B86A00" stroke-width="{7 * s:.1f}"/>
    <g transform="translate(0 {5 * s:.1f})" opacity="0.85">
      <path d="{arrow}" fill="none" stroke="#FFF6C2" stroke-width="{30 * s:.1f}" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="{head}" fill="#FFF6C2" stroke="#FFF6C2" stroke-width="{12 * s:.1f}" stroke-linejoin="round"/>
    </g>
    <path d="{arrow}" fill="none" stroke="#A35400" stroke-width="{30 * s:.1f}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="{head}" fill="#A35400" stroke="#A35400" stroke-width="{12 * s:.1f}" stroke-linejoin="round"/>
    <path d="M{p(-112, -26)} A{inner:.1f} {inner:.1f} 0 0 1 {p(-26, -112)}" fill="none" stroke="#FFFFFF" stroke-width="{14 * s:.1f}" stroke-linecap="round" opacity="0.75"/>
  </g>"""


# ---------------------------------------------------------------- the scene


def hero(dx=0.0, dy=0.0, scale=1.0):
    """The fanned cards and the coin, designed around a 1024 box; moved by
    (dx, dy) and scaled about the box centre."""
    pivot = (512, 900)
    cards = (
        card("L", 362, 200, -24, pivot, PINE, 6, "pine")
        + card("C", 362, 170, 0, pivot, MOTORS, 10, "wheel")
        + card("R", 362, 200, 24, pivot, FREIGHT, 7, "anchor")
    )
    body = cards + coin(512, 712, 152)
    return (f'<g transform="translate({dx} {dy}) translate(512 512) scale({scale}) translate(-512 -512)">'
            f"{body}</g>")


def wordmark(cx, top, size):
    """BIG over BUSINESS drawn the way LogoTitle draws it in the game, so the
    splash hands over to the lobby without a jump: a soft shadow, a brown
    extrusion, the ink outline, and a toon-shaded gold face (pale top band,
    gold middle, deep gold bottom), tilted -3 degrees.
    WHY the stroke is `outline` wide: Godot's outline size is the stroke's
    full width, half of it outside the glyph."""
    lines = [("BIG", size * 0.7), ("BUSINESS", size)]
    outline = size * 0.17
    depth = size * 0.1
    cap = 0.686  # Archivo Black cap height, in em
    y = top
    parts = []
    for text, sz in lines:
        y += sz * cap
        d, _ = text_path(text, cx, y, sz)
        solid, _ = text_path(text, cx, y, sz, solid=True)
        parts.append((d, sz, y, solid))
        y += size * 0.16
    # LogoTitle's bands, measured from the glyph top (ascent 0.878 em): pale
    # down to 40% of the ascent, gold down to 74%, deep gold below.
    pale_end = (0.878 * 0.4 - (0.878 - cap)) / cap
    gold_end = (0.878 * 0.74 - (0.878 - cap)) / cap
    out = ["<defs>"]
    for i, (_, sz, base, _s) in enumerate(parts):
        out.append(
            f'<linearGradient id="goldface{i}" gradientUnits="userSpaceOnUse" x1="0" y1="{base - sz * cap:.1f}" x2="0" y2="{base:.1f}">'
            f'<stop offset="{pale_end:.3f}" stop-color="{GOLD_PALE}"/><stop offset="{pale_end:.3f}" stop-color="{GOLD}"/>'
            f'<stop offset="{gold_end:.3f}" stop-color="{GOLD}"/><stop offset="{gold_end:.3f}" stop-color="{GOLD_DEEP}"/>'
            f'</linearGradient>')
    out.append("</defs>")
    mid = top + (y - top) / 2.0
    out.append(f'<g transform="rotate(-3 {cx} {mid:.1f})">')
    stroke = f'stroke-width="{outline:.1f}" stroke-linejoin="round"'
    for _d, _, _, d in parts:
        out.append(f'<path d="{d}" transform="translate(0 {depth + size * 0.06:.1f})" fill="#000000" opacity="0.3" '
                   f'stroke="#000000" {stroke}/>')
    for _d, _, _, d in parts:
        steps = 6
        for k in range(steps, 0, -1):
            out.append(f'<path d="{d}" transform="translate(0 {depth * k / steps:.1f})" fill="{EXTRUDE}" '
                       f'stroke="{EXTRUDE}" {stroke}/>')
    for _d, _, _, d in parts:
        out.append(f'<path d="{d}" fill="{INK}" stroke="{INK}" {stroke}/>')
    for i, (d, _, _, _s) in enumerate(parts):
        out.append(f'<path d="{d}" fill="url(#goldface{i})"/>')
    out.append("</g>")
    return "\n  ".join(out), y


def icon_svg():
    cx, cy = 512, 430
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- Generated by tools/logo_art.py; edit that, not this file. -->
  <defs>{defs_background(cx, cy, 760)}{defs_coin()}
  </defs>
  <!-- background -->
  <rect width="1024" height="1024" fill="url(#room)"/>
  {rays(cx, cy, 1100, 16, -90 + 360 / 32)}
  {sparkle(150, 210, 34)}{sparkle(880, 170, 26)}{sparkle(860, 560, 20)}{sparkle(170, 640, 18)}
  <!-- art -->
  {hero(0, -10, 1.0)}
</svg>
"""


def splash_svg():
    """Square splash: the room glow fades to NIGHT at the edges, so it sits
    seamlessly on the boot splash's NIGHT background at any aspect."""
    cx, cy = 512, 512
    mark, _ = wordmark(512, 660, 128)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- Generated by tools/logo_art.py; edit that, not this file. -->
  <defs>{defs_background(cx, cy, 500)}{defs_coin()}
  </defs>
  <rect width="1024" height="1024" fill="url(#room)"/>
  {rays(cx, cy, 520, 16, -90 + 360 / 32)}
  {sparkle(190, 240, 26)}{sparkle(840, 200, 20)}{sparkle(830, 640, 16)}
  {hero(0, -130, 0.62)}
  {mark}
</svg>
"""


def main():
    with open(os.path.join(ROOT, "client", "icon.svg"), "w") as fh:
        fh.write(icon_svg())
    os.makedirs(os.path.join(ROOT, "tools", "art"), exist_ok=True)
    with open(os.path.join(ROOT, "tools", "art", "splash.svg"), "w") as fh:
        fh.write(splash_svg())
    print("wrote client/icon.svg and tools/art/splash.svg")


if __name__ == "__main__":
    main()
