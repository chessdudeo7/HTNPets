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
