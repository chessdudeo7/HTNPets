"""Mock up the pointillist backdrop: contacts paint a picture in strokes.

    python3 tools/paintmock.py                # every background in art/
    python3 tools/paintmock.py art/night.png  # just one

Writes dist/paint.html: each background at several contact counts, with its
quantised source beside it for comparison.

Why this shape of design. Every "one mark per person" scheme caps out: beads,
spots and segments look fine at 8 and break at 30. A painting inverts that -
few strokes is sparse and abstract, many is a picture resolving, so more
contacts is the GOOD case.

Two things make it work at the counts people actually reach:

* **R2 low-discrepancy placement.** Every new stroke lands in the largest
  remaining gap, so the canvas looks evenly and deliberately covered at 8
  contacts and at 80, with no clumping and no rearranging of earlier strokes.

* **Several strokes per contact.** One dot per person fails on arithmetic:
  120 dots carries about 120 pixels of information, and nobody at a hackathon
  has 120 contacts. Clustering decouples canvas resolution from the size of
  someone's social life, and attribution survives - a contact owns its whole
  cluster, and the cursor highlights all of them together.
"""

import base64
import glob
import io
import math
import os
import sys

from PIL import Image, ImageEnhance, ImageFilter

W, H = 320, 240
COUNTS = [8, 20, 40, 80]
# Must track the app. apps/bump_pets.lua paints S.total * STROKES,
# capped by free heap; a mock that disagrees explores a design that
# is not the one shipping.
STROKES = 2
PALETTE = 10     # colours the badge will ship

# Per-background tuning. One global contrast setting cannot serve both: the
# forest is muddy and needs pushing apart, while the night scene already has
# strong separation and turns neon under the same treatment. Keyed by file
# name, falling back to a gentle default.
TUNING = {
    "forest.png": dict(contrast=1.9, colour=1.35, palette=10, blur=2),
    "night.png": dict(contrast=1.1, colour=1.0, palette=12, blur=2),
}
DEFAULT_TUNING = dict(contrast=1.25, colour=1.1, palette=10, blur=2)

# R2 low-discrepancy sequence (plastic constant).
G = 1.32471795724474602596
A1, A2 = 1.0 / G, 1.0 / (G * G)


def prepare(path):
    """Crop, resize, boost and quantise a background the way the badge will."""
    t = TUNING.get(os.path.basename(path), DEFAULT_TUNING)
    img = Image.open(path).convert("RGB")
    # Centre-crop to 4:3 before resizing: squashing a 1.54 image into 1.33
    # bends every vertical line in it.
    sw, sh = img.size
    want = W / H
    if sw / sh > want:
        nw = int(sh * want)
        img = img.crop(((sw - nw) // 2, 0, (sw - nw) // 2 + nw, sh))
    elif sw / sh < want:
        nh = int(sw / want)
        img = img.crop((0, (sh - nh) // 2, sw, (sh - nh) // 2 + nh))
    img = img.resize((W, H), Image.LANCZOS)
    # A few hundred strokes carry a few hundred pixels of information, so the
    # big regions have to be pushed apart before sampling. Sampling the raw
    # image just averages everything into one colour.
    img = ImageEnhance.Contrast(img).enhance(t["contrast"])
    img = ImageEnhance.Color(img).enhance(t["colour"])
    img = img.filter(ImageFilter.GaussianBlur(t["blur"]))
    return img.quantize(colors=t["palette"], method=Image.MEDIANCUT,
                        dither=Image.NONE).convert("RGB")


def radius_for(n):
    """Keep roughly half the canvas covered whatever the contact count."""
    r = math.sqrt(W * H * 0.55 / (n * STROKES * math.pi))
    return max(4.0, min(30.0, r))


def strokes(img, n):
    px = img.load()
    out = []
    r = radius_for(n)
    for i in range(1, n * STROKES + 1):
        x = ((0.5 + A1 * i) % 1.0) * W
        y = ((0.5 + A2 * i) % 1.0) * H
        # per-stroke jitter and size variation, so it reads as a painting
        # rather than a grid
        h = (i * 2654435761) & 0xFFFFFFFF
        x += ((h >> 3) % 9) - 4
        y += ((h >> 11) % 9) - 4
        rr = r * (0.78 + ((h >> 19) % 45) / 100.0)
        cx = min(W - 1, max(0, int(x)))
        cy = min(H - 1, max(0, int(y)))
        out.append((x, y, rr, px[cx, cy]))
    return out


CREATURE = (
    '<g opacity="0.97">'
    '<rect x="132" y="150" width="56" height="48" rx="24" fill="#f2a53c"/>'
    '<rect x="144" y="162" width="32" height="32" rx="16" fill="#ffe6c4"/>'
    '<rect x="126" y="106" width="68" height="60" rx="30" fill="#f7b04a"/>'
    '<rect x="130" y="86" width="18" height="28" rx="9" fill="#f2a53c"/>'
    '<rect x="172" y="86" width="18" height="28" rx="9" fill="#f2a53c"/>'
    '<rect x="142" y="124" width="14" height="18" rx="7" fill="#241c18"/>'
    '<rect x="164" y="124" width="14" height="18" rx="7" fill="#241c18"/>'
    '<rect x="145" y="127" width="5" height="5" rx="2.5" fill="#fff"/>'
    '<rect x="167" y="127" width="5" height="5" rx="2.5" fill="#fff"/>'
    '<rect x="156" y="145" width="8" height="6" rx="3" fill="#3a2a22"/>'
    '</g>')


def svg(img, n):
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" '
             f'height="{H}" viewBox="0 0 {W} {H}">',
             f'<rect width="{W}" height="{H}" fill="#0b0f14"/>']
    for x, y, r, (cr, cg, cb) in strokes(img, n):
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" '
                     f'fill="#{cr:02x}{cg:02x}{cb:02x}" opacity="0.88"/>')
    parts.append(CREATURE)
    parts.append("</svg>")
    return "\n".join(parts)


def embed(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def main():
    paths = sys.argv[1:] or sorted(glob.glob("art/*.png"))
    if not paths:
        sys.stderr.write("no backgrounds; put PNGs in art/\n")
        return 1

    os.makedirs("dist", exist_ok=True)
    html = ['<!doctype html><meta charset="utf-8"><title>paint mock</title>',
            '<style>body{background:#14171c;color:#c8d6e2;'
            'font:13px system-ui,sans-serif;margin:0;padding:16px}'
            'h2{font-size:14px;font-weight:600;opacity:.75;margin:22px 0 10px}'
            '.row{display:flex;flex-wrap:wrap;gap:16px}'
            'figure{margin:0}figcaption{text-align:center;padding-top:6px}'
            'svg,img{display:block;border:1px solid #2a3340}</style>']

    for path in paths:
        img = prepare(path)
        t = TUNING.get(os.path.basename(path), DEFAULT_TUNING)
        html.append(f"<h2>{os.path.basename(path)} &middot; contrast "
                    f"{t['contrast']}, {t['palette']} colours, "
                    f"{STROKES} strokes per contact</h2>")
        html.append('<div class="row">')
        html.append(f'<figure><img width="{W}" height="{H}" '
                    f'src="data:image/png;base64,{embed(img)}">'
                    f'<figcaption>source, quantised</figcaption></figure>')
        for n in COUNTS:
            html.append(f"<figure>{svg(img, n)}"
                        f"<figcaption>{n} friends &middot; {n * STROKES} "
                        f"strokes &middot; r={radius_for(n):.1f}"
                        f"</figcaption></figure>")
        html.append("</div>")
        print(path)
        for n in COUNTS:
            print(f"  {n:4d} contacts -> {n * STROKES:4d} widgets, "
                  f"radius {radius_for(n):.1f}")

    with io.open("dist/paint.html", "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(html))
    print("\ndist/paint.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
