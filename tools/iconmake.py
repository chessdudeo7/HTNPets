"""Draw the 42x42 launcher icon.

    python3 tools/iconmake.py

Writes art/icon.png at 42x42 and art/icon_preview.png at 8x for looking at.
Feed the 42x42 to the IDE's "Choose image", which converts it to the
icon.bin the badge wants.

Drawn at 8x and downscaled, so the curves are antialiased rather than
staircased. At 42 pixels there is room for one idea: the animal's head
against the night it is painting. Body, tail and feet all disappear at this
size, so they are left out rather than rendered as mud.
"""

import os

from PIL import Image, ImageDraw

S = 42
K = 8                      # supersampling factor
W = S * K

# Straight from the app: the night palette and the coat.
SKY_DARK = (12, 18, 70)
SKY_MID = (32, 46, 68)
SKY_LIT = (58, 88, 159)
STAR = (190, 215, 255)
COAT = (247, 176, 74)
COAT_DK = (226, 150, 58)
INNER = (255, 185, 198)
EYE = (36, 28, 24)
WHITE = (255, 255, 255)
NOSE = (58, 42, 34)


def ellipse(d, cx, cy, rx, ry, fill):
    d.ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K],
              fill=fill)


def main():
    img = Image.new("RGB", (W, W), SKY_DARK)
    d = ImageDraw.Draw(img)

    # A few brush strokes, so the icon says "painting" as well as "pet".
    for cx, cy, r, c in [(9, 8, 7, SKY_LIT), (33, 7, 6, SKY_MID),
                         (36, 20, 5, SKY_LIT), (5, 22, 5, SKY_MID),
                         (21, 4, 4, SKY_MID), (38, 33, 6, SKY_MID),
                         (4, 34, 5, SKY_LIT)]:
        ellipse(d, cx, cy, r, r, c)
    for cx, cy in [(12, 6), (31, 12), (7, 17)]:
        ellipse(d, cx, cy, 1.4, 1.4, STAR)

    # Ears first, so the head overlaps their bases.
    for x, rot in ((13.5, -1), (28.5, 1)):
        ellipse(d, x + rot * 0.5, 12.5, 4.2, 6.4, COAT_DK)
        ellipse(d, x + rot * 0.5, 13.2, 2.2, 3.6, INNER)

    # Head: wide, low, and large in frame. Cuteness is proportion.
    ellipse(d, 21, 25, 13.5, 12, COAT)

    # Eyes, tall rather than round, with the highlight that gives them life.
    for x in (16, 26):
        ellipse(d, x, 24.5, 2.8, 3.6, EYE)
        ellipse(d, x - 0.9, 23.2, 1.15, 1.15, WHITE)

    ellipse(d, 21, 30.5, 2.1, 1.6, NOSE)

    os.makedirs("art", exist_ok=True)
    small = img.resize((S, S), Image.LANCZOS)
    small.save("art/icon.png")
    small.resize((S * 8, S * 8), Image.NEAREST).save("art/icon_preview.png")
    print("art/icon.png        42x42, for the IDE's Choose image")
    print("art/icon_preview.png  8x, for looking at")


if __name__ == "__main__":
    main()
