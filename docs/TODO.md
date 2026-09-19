# What is left

Ordered by what bites first. Background for all of it is in
[`ARCHITECTURE.md`](ARCHITECTURE.md) and [`HARDWARE.md`](HARDWARE.md).

## Before sharing the app with anyone

**`C.STAR` is 5 and must be 25.** It is deliberately wrong so the starfield
can be tested without first meeting 25 people. The constant says so where it
is defined, and the stat line prints whatever it is set to, so a wrong value
shows on screen as `stars at 5` rather than failing silently.

**Push and look at it.** The gate is headless and has never seen the badge.

## Known and unfixed

**The painting plateaus.** Free heap at budget time is about 11,900, so the
cap lands near 52 strokes. At two strokes per contact the painting stops
growing at about 26 friends. Above that, growth shows in the creature, the
counter and the new-friend banner instead.

Raising it needs heap, and heap needs either fewer widgets or a much smaller
app. Source cuts are weak - a byte buys 1.4 to 2.5 bytes of heap against 112
per widget - and run-to-run variance in free heap is about 900 bytes, so any
saving below that cannot even be measured.

**After Connect, nothing runs until a reboot.** BLE takes ~51 KB and does not
give it back. The firmware is supposed to reboot on the way out of a radio app
and did so exactly once across several attempts. The demo beat is "bump me,
then open your pet", so a reboot sits in the middle of it - about 1.4 seconds.
Design it in rather than meeting it at the judging table.

**Two heap numbers are unexplained.** Free heap at budget time is ~11,900 when
the model predicts ~24,000. And the per-source-byte cost measured 2.55 across
builds but 1.4 within one. Neither has been chased down.

## Next feature

**The kindred trait** ([#5](https://github.com/chessdudeo7/HTNPets/issues/5))
- two badges running the app recognise each other over radio, and both gain a
trait neither could get alone. It is the only feature that gives anyone a
reason to install this on someone else's badge, and it demos with exactly the
two badges you are guaranteed to have.

It is not free:

- Headroom is a few hundred bytes. It needs more.
- It trades against strokes now that both come out of the same heap.
- It needs contact `badge_id`s to tell a kindred meeting from an ordinary one,
  and the hash ring that held them was deleted once it went unused. Some of it
  comes back.
- Radio state must live inside an existing table. The main chunk is at 23 of
  25 value-stack slots.

## Smaller

- **A background picker.** `art/` holds `night.png` (in use) and `forest.png`
  (held for this). `tools/artgen.py` bakes one background; switching at
  runtime would need both palettes resident.
- **The `2.09` figure** in `check.lua`'s `SRC_CEILING` comment is from the
  superseded model. Harmless, but wrong.
- **`.gitattributes` with `*.lua text eol=lf`.** `core.autocrlf` is `true`, so
  `wc -c` and `check.lua` disagree by exactly the line count. Left alone
  because renormalising mid-event would conflict with anything in flight.

## Things that will waste your time if you do not know them

- **`lua check.lua` passing means very little.** Every real bug here was found
  on hardware or in `tools/render.lua`, not by the gate.
- **Reboot before judging any hardware result.** The same app and size both
  passes and fails depending on what ran before.
- **Delete probe and variant apps when done.** Four installed probes were
  enough to stop the real app loading.
- **Declare locals above the code that closes over them.** Two tests in
  `test/mockbadge.lua` were silently testing nothing because a flag was
  declared below the table that read it.
- **Anything that adapts to free memory needs a floor and a log line.** The
  painting once degraded all the way to zero strokes and said nothing.
