# Backgrounds

Source images for the pointillist backdrop. Each contact paints a cluster of
strokes; the strokes take their colour from one of these.

| file | notes |
| --- | --- |
| `night.png` | Night sky, moon, hills. Currently the chosen one. |
| `forest.png` | Layered forest silhouettes. Held for a later background picker. |

`tools/paintmock.py` renders every image here at several contact counts, so a
candidate can be judged before any of it reaches a badge:

```bash
python3 tools/paintmock.py
```

## What makes a good background here

A few hundred strokes carry a few hundred pixels of information, so this is
roughly a 15x15 image however much care goes into the source.

- **Big regions, strong light/dark separation.** The night scene works because
  it is four shapes: sky, swirl, moon, hills.
- **Fine detail is lost.** The forest's thin trunks never survive, which is why
  it reads as abstract green until about 40 contacts.
- **Tune per image.** `TUNING` in `paintmock.py` holds contrast, saturation and
  palette size per file. One global setting cannot serve both: the forest is
  muddy and needs pushing apart, while the night scene turns neon under the
  same treatment.

## The launcher icon

`icon.png` is 42x42, the size the badge wants. Feed it to the IDE's
**Choose image**, which converts it to the `icon.bin` the launcher reads
and overrides the manifest's text icon.

```bash
python3 tools/iconmake.py
```

That also writes `icon_preview.png` at 8x for looking at, since 42 pixels
is hard to judge at actual size.

At this size there is room for one idea: the animal's head against the
night it is painting. Body, tail and feet are left out rather than
rendered as mud. It is drawn at 8x and downscaled so the curves are
antialiased instead of staircased.
