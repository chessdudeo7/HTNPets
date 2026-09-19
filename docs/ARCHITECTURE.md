# How Bump Pets is built

For picking the app up cold. The hardware limits that shape all of it are in
[`HARDWARE.md`](HARDWARE.md); this is how the code answers them.

## What it does

Reads the Connect address book. Each contact paints brush strokes on a
backdrop, so the people you meet assemble a picture. A creature stands in
front of it, its species fixed by your badge id and its size growing with your
contact count. Left and Right walk the contacts and name the strokes each one
painted.

Nothing is simulated and nothing is saved about the creature. Open the app and
it rebuilds itself from the contacts book. That is deliberate: it cannot
desynchronise from reality, it survives a reinstall, and a copy shared to
another badge grows from *their* contacts rather than cloning yours.

## The bounded work queue

**`on_enter` draws one label and returns.** Everything else happens one small
step per `on_tick`, driven by `P.step`. This is not a style choice - the badge
raises "Lua stack safety limit reached" when a callback does too much, and the
vendor guide's remedy for that exact message is an explicit bounded work
queue.

| step | does |
| --- | --- |
| 1 | read the store: led state, brightness, `seen`, `hatch` |
| 2 | badge id, pet name, species |
| 3 | scan contacts, **one per tick**, then decide the stroke budget |
| 4-18 | create stroke widgets, eight per tick |
| 19-23 | create the creature's boxes, four per tick |
| 24-28 | the mouth line and the labels |
| 40 | `meta()`: layout and the attribution window |
| 41-55 | `paint()`: position and colour the strokes, eight per tick |
| 56-58 | `dress()`: size and colour the creature, in three batches |
| 59 | `finish()`: text, progress bar, show or hide for the egg |
| 60+ | celebrate a new friend, then `P.step = 0` and the app is live |

`on_button` returns immediately while `P.step > 0`, so input cannot land
half-built. A rescan (A) jumps back to step 3 and then to 40, skipping
creation because `P.made` is set.

**Do not move work back into `on_enter`.** Do not wrap `string.byte` in a
loop.

## Creation order is z-order

LVGL stacks children in the order they are made and there is no z-index. That
is why strokes are created before the creature and labels last: strokes must
sit behind, labels in front. `C.MK` lists the creature's boxes in the order
they stack, so reordering that table reorders the drawing.

## The stroke budget

Decided at the end of step 3, **before any widget exists**, and stored on `P`:

```lua
local cap = (badge.sys.stats().free_heap - 6000) // 112
n = min(S.total * 2, cap), floored at C.MINS
```

Three things matter here:

- **It asks the heap, rather than assuming.** A count tuned on a clean badge
  fails on one with other apps installed - which is every badge this gets
  shared to.
- **Only `n` widgets are created.** Creating `C.MAXS` and hiding the rest
  leaks about 112 bytes per hidden widget; that bug left the app running on
  2.2 KB of heap.
- **There is a floor.** Without `C.MINS` the cap can reach zero and the app
  draws a creature in front of an empty sky. `check.lua` asserts a badge with
  contacts never paints nothing.

Contacts cannot change while the app is in the foreground, because bumping
means leaving it. That is what makes it safe to size the widgets once.

## Where the strokes go

Positions come from the **R2 low-discrepancy sequence**, so every stroke lands
in the largest remaining gap. The canvas looks deliberately covered at 5
contacts and at 200, and nothing rearranges as it grows. Radius scales with
`1/sqrt(n)` to hold coverage near half the canvas at any count.

Colours are **baked at build time** by `tools/artgen.py`, which walks the same
sequence over a source image and writes `C.PAL` and `C.ART`. The badge never
sees an image: 262 bytes of palette and index string instead of kilobytes.

Past the budget the painting covers the **most recent** contacts, not the
first - see below.

## Attribution, and why it stops at 16

`S.nm` is a ring of the last **16** contact names. Retaining every record
would cost real heap, so only those contacts can be named, and the cursor
walks that window.

This is also why the painting follows recent contacts when the budget binds.
Painting from the front while naming from the back would point at one person
and name another - which it did, showing `#2  Person 34` at 40 contacts.

- `S.sel` - how many contacts are selectable
- `S.poff` - offset into the strokes
- `S.base` - offset into the contact book

## The egg

`S.hatch` is the contact count the egg was armed at, written once on the first
open. `S.egg` is `S.total <= S.hatch`, recomputed every scan. So everyone
hatches on their **next** bump however many contacts they already had, and a
fresh Share install re-arms it - which makes the install the demo's opening
move.

`dist/bump_pets_nohatch.lua` is a generated variant with the arming patched
out, for looking at the creature without finding someone new to bump. It is
generated rather than a second copy: `build.lua` fails if the patch stops
matching.

## The leds

| state | shows |
| --- | --- |
| celebrating | a chase in the coat colour |
| egg | all six breathing amber, 35-100% |
| `S.total >= C.STAR` | a starfield, each led on its own period |
| otherwise | the coat colour, with one travelling highlight |

Two gotchas, both learned the hard way. **The firmware's brightness curve
flattens small values** - two leds at 15-50% read as off, which shipped once;
`test/mockbadge.lua` now enforces a visible peak. And **evenly spaced offsets
make six leds ramp in order**, which reads as a wave rather than stars, so the
starfield offsets are squared.

## Constants worth knowing

| name | what |
| --- | --- |
| `C.STAR` | contacts that unlock the starfield. **Must be 25 for the event.** |
| `C.MAXS` | hard ceiling on strokes, above whatever the heap allows |
| `C.MINS` | strokes painted however tight the heap is |
| `C.SP` | the four species: ear and tail geometry as 34ths of head width |
| `C.MK` | the creature's boxes, in stacking order |
| `C.PAL`, `C.ART` | generated; re-run `tools/artgen.py` to change background |

## The tools

| tool | for |
| --- | --- |
| `check.lua` | the gate. Run before every push. |
| `build.lua` | minifies into `dist/`, proves equivalence by disassembly |
| `tools/render.lua` | draws the real widget tree as SVG, for seeing the design |
| `tools/paintmock.py` | mocks backdrops before they reach the badge |
| `tools/artgen.py` | bakes a background into `C.PAL` and `C.ART` |
| `tools/ceilingprobe.lua` | padded apps at exact sizes, for measuring limits |
| `tools/iconmake.py` | the 42x42 launcher icon |

`tools/render.lua` is the one worth knowing about. The design decisions in
this app were made by looking at its output - an ASCII silhouette can tell you
something is on screen, not whether it is any good.
