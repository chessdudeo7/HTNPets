# HTNPets — Bump Pets

Badge apps for Hack the North 2026. The repo is the source of truth; the
[Badge IDE](https://badge.hackthenorth.com/ide/) is only the flashing tool —
its workspace lives in browser localStorage, so nothing is safe there.

## Apps

| File | Slug | What |
| --- | --- | --- |
| `apps/bump_pets.lua` | `htn_bump_pets` | The pet. A creature built from your Connect contacts. |
| `apps/bump_probe.lua` | `bump_probe` | Read-only diagnostic. Push this first on a new badge. |

`apps/bump_pets.lua` used to be a segmented worm, and `wip/animal.lua` an
unfinished round-animal redesign shelved for being over the compile-memory
ceiling. The animal became the app; the worm is in git history.

Each file is a complete app in the single-file format: the `--[==[badge-app`
header becomes `manifest.cfg`, everything after `]==]` becomes `main.lua`.
Keep them single-file — the format only packages those two, so extra modules
would have to be maintained by hand in the IDE.

## Check before every push

```powershell
.\check.ps1
```

```bash
lua check.lua
```

Build, lint, Lua syntax, the value-stack slot budget, and a headless run of the
real app against a mock badge API at 0, 1, 5, 12, 40 and 200 contacts. Exits
non-zero on failure. If this fails, pushing will fail.

## The build step, and why you paste from dist/

`build.lua` (run for you by `check.lua`) writes a byte-reduced copy of each app
into `dist/`. It removes whole-line comments and leading indentation, never
reflows code, and never touches a line that is not entirely a comment. It then
proves the result by disassembling both copies with `luac -l` and comparing the
instruction streams with line markers and heap addresses normalised out. A
mismatch fails the build instead of shipping a guess.

This matters because the compile-memory ceiling is spent on **source bytes**,
and comments cost a reader nothing while costing the badge real RAM:

| | source | dist | ceiling | headroom |
| --- | --- | --- | --- | --- |
| `apps/bump_pets.lua` | 22,090 | 14,458 | 14,500 | 42 |

### Test variants

`build.lua` also emits variants: the real app with a small documented source
patch, under its own slug, so one can sit beside the real one on a badge.

| file | slug | what |
| --- | --- | --- |
| `dist/bump_pets_nohatch.lua` | `bump_nohatch` | Always hatched. For looking at the animal without needing a fresh bump. |

Variants are generated, never hand-maintained - a second copy of the app in
the repo means every fix has to be made twice, and the copy nobody remembers
to update is the one someone tests against. If a patch stops matching the app,
`build.lua` fails rather than silently emitting an unpatched variant.

Delete a variant off the badge when you are done with it. Each installed app
costs registry memory, and this app has very little to spare.

**Paste `dist/bump_pets.lua` into the IDE, not `apps/bump_pets.lua`.** The
ceiling in `check.lua` is measured against `dist/`. `dist/` is gitignored, and
`lua check.lua` regenerates it, so run the gate before you copy.

### The ceiling

**Read [`docs/HARDWARE.md`](docs/HARDWARE.md) before changing `SRC_CEILING`.**
It holds the measurements, and they are not what anyone expects: the limit is
the largest contiguous block rather than a byte count, it moves with whatever
ran before, and prototype count is a second budget worth about 112 bytes each.

To measure a size yourself:

```bash
lua tools/ceilingprobe.lua 14500
```

That writes `dist/ceil_14500.lua`, padded to exactly that size with code of
realistic shape. Each probe carries its own slug, so several install side by
side and none of them touches `htn_bump_pets`. Push, open, and read the screen:
it prints its size and heap stats, or dies in `main.lua`.

**Reboot first, and delete the probes afterwards.** Both of those changed the
answer here: a fragmented heap failed a size that passed from a clean boot, and
four installed probes were enough to stop the real app loading.

### A note on byte counts

`wc -c` and `check.lua` disagree by exactly the line count. `core.autocrlf` is
`true`, so the working tree holds CRLF while Lua's text-mode read collapses it
to LF. **`check.lua`'s number is the authoritative one** - it matches what the
compiler sees. Do not budget against `wc -c`.

Needs Lua 5.4 (`winget install DEVCOM.Lua`), installed to
`%LOCALAPPDATA%\Programs\Lua\bin`. `check.ps1` locates it even when `lua` is
not on PATH — a terminal opened before the install keeps a stale PATH, and in
VS Code a new terminal tab inherits it too, so only restarting VS Code fixes
that. To patch the current session instead:

```powershell
$env:Path += ";$env:LOCALAPPDATA\Programs\Lua\bin"
```

## Pushing to a badge

Copy the built app to the clipboard (run `lua check.lua` first):

```powershell
Get-Content -Raw dist\bump_pets.lua | Set-Clipboard
```

```bash
cat dist/bump_pets.lua | clip
```

Or just open the file and Ctrl+A, Ctrl+C — that always works.

Then in the IDE: **Import app** → paste → confirm the slug → **Replace editor
files** → **Push** → open it on the badge with **A**.

Before the first push: badge off, USB **data** cable in, badge on *without*
holding Start, desktop Chrome or Edge, no other tab holding the serial port.
Pick **USB JTAG/serial debug unit** in the device picker.

- Code edits need **Push** and reopening the app.
- Manifest edits (`api`, `heap_kb`, `wake_lock`, `home_button`, `confirm_home`)
  need a **Reboot** — a rescan only refreshes name and icon.
- `[push] reload confirmed` means uploaded and rescanned, **not** that the app
  ran. Read the badge screen and the console too.

## Constraints

The memory ones - the ceiling, why it moves, what Connect does to the heap -
are in [`docs/HARDWARE.md`](docs/HARDWARE.md), measured. They are not repeated
here; the copy nobody amends is the one someone reads.

The rest:

- **"Lua stack safety limit reached" is about value-stack slots**, not about
  loops or heap. Keep the main chunk and every function under ~25 slots. State
  belongs in a few tables, not in dozens of file-level locals - each local
  costs a main-chunk slot and an upvalue in every function that reads it.
  Measure with `luac -l apps/bump_pets.lua | grep slots`.
- **Never wrap `string.byte` in a loop.** Fetch bytes in bulk.
- `heap_kb=96` is required, not optional - this app does not fit in 48 KB.
- **Contacts carry no usable `received_unix`** on this firmware, so contact
  index order is the only ordering available.
- `badge_id` is a 23-character word slug like `moon-honey-opal-bloom`.
- Coordinates and RGB channels must be **integers**. Prefer `//` over
  `math.floor`: it is a VM opcode, not a C call.
- 320x240 screen, 512 native widgets, 64 KiB `main.lua`, 48 KiB Share bundle.
- No `pcall`, so every nil must be guarded by hand.
- LED indices are 1-based. Front view: 1 upper-left, 2 upper-right,
  3 middle-right, 4 bottom-right, 5 bottom-left, 6 middle-left.
