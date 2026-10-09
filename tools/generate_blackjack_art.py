#!/usr/bin/env python3
"""Generate the original 52-card blackjack deck and matching geometric back.

Requires Pillow only; generation is not needed to run the game. Run from any
directory with ``python tools/generate_blackjack_art.py``. The artwork consists
entirely of original vector geometry and typeset ranks; no brand assets are used.
Pass --font /path/to/font.ttf to select a different bold rank font. Output is
deterministic for a given Pillow version and font. Cards are 384 x 544 RGBA PNGs.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT, SCALE = 384, 544, 3
ROOT = Path(__file__).resolve().parents[1] / "assets" / "blackjack"
IVORY = "#fcf8ef"
EDGE = "#d7c9ae"
BLACK = "#182933"
RED = "#b72d42"
GOLD = "#b18a49"
PALE_GOLD = "#e8dcc4"
GREEN = "#123c3c"
SUITS = ("clubs", "diamonds", "hearts", "spades")


class Canvas:
    def __init__(self, size=(WIDTH, HEIGHT)):
        self.im = Image.new("RGBA", (size[0] * SCALE, size[1] * SCALE))
        self.d = ImageDraw.Draw(self.im)

    def box(self, box):
        return tuple(round(x * SCALE) for x in box)

    def line(self, points, color, width=1):
        self.d.line(self.box(points), fill=color, width=round(width * SCALE))

    def polygon(self, points, color):
        self.d.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color)

    def ellipse(self, box, color):
        self.d.ellipse(self.box(box), fill=color)

    def rounded(self, box, radius, fill=None, outline=None, width=1):
        self.d.rounded_rectangle(self.box(box), radius=round(radius * SCALE),
                                 fill=fill, outline=outline, width=round(width * SCALE))

    def text(self, xy, value, size, color, font_path):
        font = ImageFont.truetype(str(font_path), round(size * SCALE))
        # Center on the visible glyph bounds, avoiding font-specific baseline drift.
        bounds = self.d.textbbox((0, 0), value, font=font)
        x = xy[0] * SCALE - (bounds[0] + bounds[2]) / 2
        y = xy[1] * SCALE - (bounds[1] + bounds[3]) / 2
        self.d.text((round(x), round(y)), value, font=font, fill=color)

    def finish(self):
        return self.im.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)


def cubic(a, b, c, d, steps=20):
    return [((1-t)**3*a[0]+3*(1-t)**2*t*b[0]+3*(1-t)*t*t*c[0]+t**3*d[0],
             (1-t)**3*a[1]+3*(1-t)**2*t*b[1]+3*(1-t)*t*t*c[1]+t**3*d[1])
            for t in (i / steps for i in range(steps + 1))]


def suit(canvas, name, x, y, size, color, inverted=False):
    """Draw suits from circles and original sampled cubic curves, not font glyphs."""
    direction = -1 if inverted else 1

    def transform(points):
        return [(x + px * size * direction, y + py * size * direction) for px, py in points]

    def poly(points):
        canvas.polygon(transform(points), color)

    if name == "diamonds":
        poly([(0, -.56), (.39, 0), (0, .56), (-.39, 0)])
    elif name == "hearts":
        points = cubic((0, -.27), (-.22, -.66), (-.62, -.37), (-.43, -.02))
        points += cubic((-.43, -.02), (-.30, .20), (-.12, .37), (0, .52))
        points += cubic((0, .52), (.12, .37), (.30, .20), (.43, -.02))
        points += cubic((.43, -.02), (.62, -.37), (.22, -.66), (0, -.27))
        poly(points)
    elif name == "spades":
        points = cubic((0, -.56), (-.15, -.34), (-.62, -.08), (-.43, .23))
        points += cubic((-.43, .23), (-.30, .44), (-.08, .34), (0, .17))
        points += cubic((0, .17), (.08, .34), (.30, .44), (.43, .23))
        points += cubic((.43, .23), (.62, -.08), (.15, -.34), (0, -.56))
        poly(points)
        poly([(-.065, .12), (.065, .12), (.12, .44), (.23, .53), (-.23, .53), (-.12, .44)])
    elif name == "clubs":
        for cx, cy in [(0, -.28), (-.25, .06), (.25, .06)]:
            cx, cy = x + cx * size * direction, y + cy * size * direction
            radius = .255 * size
            canvas.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), color)
        poly([(-.07, .05), (.07, .05), (.13, .42), (.24, .53), (-.24, .53), (-.13, .42)])


def base():
    c = Canvas()
    c.rounded((1, 1, WIDTH-2, HEIGHT-2), 22, IVORY, EDGE, 1.5)
    c.rounded((10, 10, WIDTH-11, HEIGHT-11), 15, outline=PALE_GOLD, width=.65)
    return c


def corners(c, name, rank, ink, font):
    label = {1: "A", 11: "J", 12: "Q", 13: "K"}.get(rank, str(rank))
    corner = Canvas()
    corner.text((48, 52), label, 53 if rank != 10 else 45, ink, font)
    suit(corner, name, 48, 103, 34, ink)
    c.im.alpha_composite(corner.im)
    c.im.alpha_composite(corner.im.transpose(Image.Transpose.ROTATE_180))


def pip_positions(rank):
    # Symmetric traditional pip layouts; lower-half pips face the opposite end.
    left, center, right = 123, 192, 261
    top, upper, lower, bottom = 127, 224, 320, 417
    layouts = {
        2: [(center, top), (center, bottom)],
        3: [(center, top), (center, 272), (center, bottom)],
        4: [(left, top), (right, top), (left, bottom), (right, bottom)],
        5: [(left, top), (right, top), (center, 272), (left, bottom), (right, bottom)],
        6: [(x, y) for y in (top, 272, bottom) for x in (left, right)],
        7: [(x, y) for y in (top, 272, bottom) for x in (left, right)] + [(center, 199.5)],
        8: [(x, y) for y in (top, 272, bottom) for x in (left, right)] + [(center, 199.5), (center, 344.5)],
        9: [(x, y) for y in (top, upper, lower, bottom) for x in (left, right)] + [(center, 272)],
        10: [(x, y) for y in (top, upper, lower, bottom) for x in (left, right)] + [(center, 175.5), (center, 368.5)],
    }
    return layouts[rank]


def court(c, name, rank, ink, font):
    # A deliberately geometric, double-ended court seal, original to this deck.
    c.rounded((87, 84, 297, 460), 11, outline=GOLD, width=1.5)
    c.rounded((94, 91, 290, 453), 7, outline=PALE_GOLD, width=.9)
    c.polygon([(192, 125), (269, 272), (192, 419), (115, 272)], PALE_GOLD)
    c.polygon([(192, 138), (258, 272), (192, 406), (126, 272)], IVORY)
    # Three distinct crown profiles, with mirrored ornament at the lower end.
    top = Canvas()
    crown_y = 155
    if rank == 11:
        points = [(156, crown_y+16), (159, crown_y-6), (174, crown_y+6), (192, crown_y-16), (210, crown_y+6), (225, crown_y-6), (228, crown_y+16)]
    elif rank == 12:
        points = [(158, crown_y+16), (151, crown_y-8), (173, crown_y+2), (192, crown_y-24), (211, crown_y+2), (233, crown_y-8), (226, crown_y+16)]
    else:
        points = [(156, crown_y+16), (150, crown_y-14), (173, crown_y+1), (192, crown_y-24), (211, crown_y+1), (234, crown_y-14), (228, crown_y+16)]
    top.polygon(points, GOLD)
    top.line((159, crown_y+22, 225, crown_y+22), ink, 3)
    suit(top, name, 192, 201, 25, ink)
    c.im.alpha_composite(top.im)
    c.im.alpha_composite(top.im.transpose(Image.Transpose.ROTATE_180))
    c.rounded((132, 223, 252, 321), 8, IVORY)
    c.text((192, 271), {11: "J", 12: "Q", 13: "K"}[rank], 109, ink, font)
    for x in (107, 277):
        c.polygon([(x, 263), (x+5, 272), (x, 281), (x-5, 272)], GOLD)


def face(name, rank, font):
    c = base()
    ink = RED if name in ("hearts", "diamonds") else BLACK
    corners(c, name, rank, ink, font)
    if rank == 1:
        suit(c, name, 192, 272, 131, ink)
        for y in (169, 375):
            c.polygon([(192, y-5), (197, y), (192, y+5), (187, y)], GOLD)
    elif rank <= 10:
        for x, y in pip_positions(rank):
            suit(c, name, x, y, 47, ink, inverted=y > 272)
    else:
        court(c, name, rank, ink, font)
    return c.finish()


def back():
    c = base()
    c.rounded((16, 16, 368, 528), 13, GREEN)
    c.rounded((25, 25, 359, 519), 8, outline=GOLD, width=1.6)
    c.rounded((32, 32, 352, 512), 5, outline="#739383", width=.75)
    # Clipped art-deco lattice. The entire design has half-turn symmetry.
    for x in range(49, 350, 26):
        for y in range(51, 505, 26):
            c.polygon([(x, y-5), (x+3, y), (x, y+5), (x-3, y)], "#2b5750")
    c.polygon([(192, 84), (315, 272), (192, 460), (69, 272)], GOLD)
    c.polygon([(192, 90), (309, 272), (192, 454), (75, 272)], GREEN)
    c.polygon([(192, 104), (299, 272), (192, 440), (85, 272)], "#31564e")
    c.polygon([(192, 111), (293, 272), (192, 433), (91, 272)], GREEN)
    for y in (62, 482):
        c.line((125, y, 175, y), GOLD, 1)
        c.line((209, y, 259, y), GOLD, 1)
        c.polygon([(192, y-7), (197, y), (192, y+7), (187, y)], GOLD)
    # Eight-point compass motif with a quiet center medallion.
    points = []
    for i in range(16):
        theta = -math.pi/2 + i*math.pi/8
        radius = 74 if i % 2 == 0 else 32
        points.append((192+math.cos(theta)*radius, 272+math.sin(theta)*radius))
    c.polygon(points, GOLD)
    c.ellipse((167, 247, 217, 297), IVORY)
    c.ellipse((171, 251, 213, 293), GREEN)
    c.polygon([(192, 257), (202, 272), (192, 287), (182, 272)], GOLD)
    return c.finish()


def find_font(requested):
    candidates = [Path(requested)] if requested else [
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
        Path("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf"),
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
    ]
    for path in candidates:
        if path.is_file():
            return path
    raise SystemExit("No bold font found; pass --font /path/to/font.ttf")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", help="Bold TrueType/OpenType font for card ranks")
    parser.add_argument("--output", type=Path, default=ROOT, help="Output directory")
    args = parser.parse_args()
    font = find_font(args.font)
    args.output.mkdir(parents=True, exist_ok=True)
    for name in SUITS:
        for rank in range(1, 14):
            face(name, rank, font).save(args.output / f"{name}_{rank}.png", optimize=True)
    back().save(args.output / "back.png", optimize=True)
    print(f"Generated 52 faces and 1 back at {WIDTH}x{HEIGHT} in {args.output}")


if __name__ == "__main__":
    main()
