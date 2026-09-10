#!/usr/bin/env python3
# Copyright (c) 2026 dzwiedziu-nkg
# SPDX-License-Identifier: AGPL-3.0-only
"""Draws the two order diagrams in doc/ over a screenshot of the test model.

The pillar positions below were measured off that screenshot; re-measure them if it
is ever retaken. Usage: figures.py <screenshot.png> <output directory>
"""

from PIL import Image, ImageDraw, ImageFont
import math, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "doc/test_model.png"
OUT = sys.argv[2] if len(sys.argv) > 2 else "doc"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

PILLARS = [(119,205),(216,194),(312,182),(408,170),(502,159),(596,148),(689,137),
           (781,126),(872,115),(962,104),(1051,93),(1140,82),(1227,72),(1314,61),(1405,50)]
# bottom edge of the base plate directly under each pillar, so the return sweep can
# hug the model instead of floating on a straight line under it
PLATE_BOTTOM = [324,312,300,287,276,264,252,240,229,217,206,195,184,173,161]

TOP_PAD, BOT_PAD = 78, 96
BG = (26, 26, 28)
YELLOW  = (255, 205, 20)
BLUE    = (110, 200, 255)
RED     = (255, 82, 72)
WHITE   = (238, 238, 238)
GREY    = (150, 150, 155)


def bezier(p0, p1, p2, n=90):
    return [((1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t*t*p2[0],
             (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t*t*p2[1])
            for t in (i/n for i in range(n+1))]


def arc(draw, a, b, colour, above=True, lift=52, width=5, head=15):
    """Curved arrow from a to b, bulging above or below."""
    mx, my = (a[0]+b[0])/2, (a[1]+b[1])/2
    ctrl = (mx, my - lift) if above else (mx, my + lift)
    pts = bezier(a, ctrl, b)
    draw.line(pts, fill=colour, width=width, joint="curve")
    # arrowhead along the final tangent
    x1, y1 = pts[-1]; x0, y0 = pts[-6]
    ang = math.atan2(y1-y0, x1-x0)
    for s in (+1, -1):
        t = ang + s*math.radians(155)
        draw.line([(x1, y1), (x1 + head*math.cos(t), y1 + head*math.sin(t))],
                  fill=colour, width=width)


def build(order, colours, aboves, caption, sub, out, note=None, note_colour=RED):
    shot = Image.open(SRC).convert("RGB")
    W, H = shot.size
    im = Image.new("RGB", (W, H + TOP_PAD + BOT_PAD), BG)
    im.paste(shot, (0, TOP_PAD))
    d = ImageDraw.Draw(im)

    pts = [(x, y + TOP_PAD) for x, y in PILLARS]

    # caption
    d.text((28, 20), caption, font=ImageFont.truetype(FONTB, 34), fill=WHITE)
    d.text((28, 58), sub, font=ImageFont.truetype(FONT, 19), fill=GREY)

    # pillar numbers, just under each cube
    fnum = ImageFont.truetype(FONTB, 17)
    for i, (x, y) in enumerate(pts, 1):
        t = str(i)
        w = d.textbbox((0, 0), t, font=fnum)[2]
        d.text((x - w/2, y + 30), t, font=fnum, fill=(255, 255, 255))

    # hops
    for (i, j), colour, above in zip(order, colours, aboves):
        a, b = pts[i], pts[j]
        if above:
            arc(d, (a[0], a[1]-14), (b[0], b[1]-14), colour, True,
                lift=34 + 5*abs(i-j), width=5)
        else:
            ay = PLATE_BOTTOM[i] + TOP_PAD + 14
            by = PLATE_BOTTOM[j] + TOP_PAD + 14
            arc(d, (a[0], ay), (b[0], by), colour, False,
                lift=24 + min(52, 3*abs(i-j)), width=6)

    if note:
        f = ImageFont.truetype(FONTB, 21)
        w = d.textbbox((0, 0), note, font=f)[2]
        d.text((W - w - 28, im.size[1] - 34), note, font=f, fill=note_colour)

    im.save(out)
    print("zapisano", out, im.size)


# --- bez pluginu: 1..15 po kolei, potem długi powrót do 1 -------------------
order   = [(i, i+1) for i in range(14)] + [(14, 0)]
colours = [YELLOW]*14 + [RED]
aboves  = [True]*14 + [False]
build(order, colours, aboves,
      "Without the plugin",
      "One order chained at slicing time and reused on every layer: along the row, then all the way back to the start.",
      OUT + "/island_order_stock.png",
      note="longest single travel 275.6 mm")

# --- z pluginem: 1,3,5..15 górą, 14,12..2 dołem ----------------------------
out_idx = list(range(0, 15, 2))          # 1,3,5,...,15
back_idx = list(range(13, 0, -2))        # 14,12,...,2
seq = out_idx + back_idx
order   = [(seq[k], seq[k+1]) for k in range(len(seq)-1)]
# outward hops ride above the row; the turn at the far end and the whole return
# sweep run below it, so the two passes never overlap
aboves  = [True]*(len(out_idx)-1) + [False]*len(back_idx)
colours = [YELLOW]*(len(out_idx)-1) + [BLUE]*len(back_idx)
build(order, colours, aboves,
      "With the plugin",
      "One order for every layer, walked in steps of two: out along the odd islands, back along the even ones.",
      OUT + "/island_order_plugin.png",
      note="longest single travel 44.4 mm", note_colour=(120, 220, 140))
