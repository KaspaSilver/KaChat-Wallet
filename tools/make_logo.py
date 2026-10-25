"""Draws the KaChat Wallet logo: a teal wallet with Kaspa's backward K, on a white rounded square.

Usage: python3 tools/make_logo.py OUT.png [SIZE]   (default 1024)
"""
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
size = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
S = 4  # supersampling
W = 1024 * S

def p(*xy):
    return [v * S for v in xy]

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# White rounded square, like the KaChat logo's tile.
d.rounded_rectangle(p(0, 0, 1023, 1023), radius=230 * S, fill=(255, 255, 255, 255))

TEAL_TOP = (138, 214, 201)
TEAL_BOTTOM = (95, 191, 176)
TEAL_DARK = (72, 166, 151)

# The note peeking out of the wallet's top.
d.rounded_rectangle(p(250, 225, 790, 380), radius=48 * S, fill=TEAL_DARK)

# Wallet body, with a soft top-to-bottom gradient.
body = (165, 300, 859, 790)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle(p(*body), radius=96 * S, fill=255)
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
for y in range(body[1] * S, body[3] * S + 1):
    t = (y - body[1] * S) / ((body[3] - body[1]) * S)
    c = tuple(round(a + (b - a) * t) for a, b in zip(TEAL_TOP, TEAL_BOTTOM))
    gd.line([(0, y), (W, y)], fill=c + (255,))
img.paste(grad, (0, 0), mask)

# Clasp on the right edge, with its button.
d.rounded_rectangle(p(690, 465, 899, 625), radius=56 * S, fill=TEAL_DARK)
d.ellipse(p(752, 521, 800, 569), fill=(255, 255, 255, 255))

# Kaspa's backward K, centred on the wallet: a slightly leaning bar with a ">" pointing into it.
WHITE = (255, 255, 255, 255)
d.polygon(p(572, 402, 632, 398, 617, 690, 557, 694), fill=WHITE)  # bar
stroke = 60
d.line(p(390, 428, 572, 546), fill=WHITE, width=stroke * S)       # upper arm
d.line(p(390, 664, 572, 546), fill=WHITE, width=stroke * S)       # lower arm
d.polygon(p(542, 512, 584, 546, 542, 580, 512, 546), fill=WHITE)  # fills the arms' join

img = img.resize((size, size), Image.LANCZOS)
img.save(out)
