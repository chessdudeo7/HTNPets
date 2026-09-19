# HTNPets — Bump Pets

Badge apps for Hack the North 2026. The repo is the source of truth; the
[Badge IDE](https://badge.hackthenorth.com/ide/) is only the flashing tool —
its workspace lives in browser localStorage, so nothing is safe there.

## Apps

| File | Slug | What |
| --- | --- | --- |
| `apps/bump_pets.lua` | `htn_bump_pets` | The pet. A creature built from your Connect contacts. |
| `apps/bump_probe.lua` | `bump_probe` | Read-only diagnostic. Push this first on a new badge. |

`wip/animal.lua` is an unfinished redesign that replaces the segmented worm
with a round animal — four species, contacts as coloured spots, blinking.
It is complete and passes the headless harness. At 15,670 bytes of source it
was 2,670 over the compile-memory ceiling and died in `main.lua` on the badge.

**Minified it is 12,524 bytes, which is under the ceiling with 476 to spare.**
That is worth one push to find out, but treat it as untested: 13,000 is a
conservative line drawn between one measurement that ran (11,575) and one that
failed (15,670), so 12,524 sits in the band nobody has probed. If it dies in
`main.lua`, the ceiling is real and lower than 12,524 — record the number.

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

| | source | dist | headroom to 13,000 |
| --- | --- | --- | --- |
| `apps/bump_pets.lua` | 11,575 | 9,376 | 3,624 |

**Paste `dist/bump_pets.lua` into the IDE, not `apps/bump_pets.lua`.** The
ceiling in `check.lua` is measured against `dist/`. `dist/` is gitignored, and
`lua check.lua` regenerates it, so run the gate before you copy.

### Finding the real ceiling

13,000 is a conservative line, not a measurement. It decides whether the
`wip/animal.lua` redesign fits. Measured on hardware so far:

| file bytes | prototypes | result |
| --- | --- | --- |
| 11,575 | 21 | loads |
| 12,524 | 19 | loads (`wip/animal.lua`) |
| 13,750 | **137** | fails, `used 60864 / limit 98304, peak 61128` |
| 15,670 | 19 | fails |

**Prototype count is its own budget.** That 13,750 row came from the first
version of the probe, which padded with 137 tiny functions where a real app of
that size has about 19. Every Lua `Proto` carries a constant array, upvalue
descriptors, a code array and debug info, so it hit the allocator early and
measured its own shape rather than its size. The probe now pads at the real
apps' density, about 750 body bytes per prototype. Read that row as evidence
about function count, not about bytes.

The consequence for app code: splitting logic into many small helper functions
is not free.

```bash
lua tools/ceilingprobe.lua 13750
```

That writes `dist/ceil_13750.lua`, an app padded to exactly that size with
representative code. Push it, open it, and read the screen:

- **It opens** and prints its size and heap stats. That size is proven good.
- **It dies in `main.lua`** with `Lua memory limit exceeded` before `on_enter`
  runs. That size is proven bad.

Test the size you actually want first, not the midpoint - if 13,750 loads
there is nothing left to search. Only bisect downward if it fails. Every probe
shares the slug `ceil_probe`, so they overwrite each other and never touch
`htn_bump_pets`. **Reboot between pushes:** a failed Lua state can leave memory
retained, which biases the next result.

Record what you find in the table above and raise `SRC_CEILING` in `check.lua`
to the highest proven-good size, minus a margin.

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

## Hard-won constraints

Learned on hardware, mostly the painful way:

- **"Lua stack safety limit reached" is about value-stack slots**, not about
  loops or heap. Keep the main chunk and every function under ~25 slots. State
  belongs in a few tables, not in dozens of file-level locals — each local
  costs a main-chunk slot and an upvalue in every function that reads it.
  Measure with `luac -l apps/bump_pets.lua | grep slots`.
- **Never wrap `string.byte` in a loop.** Fetch bytes in bulk.
- **Source size has a hard ceiling around 12-13 KB.** The whole chunk is
  parsed and compiled before any callback runs, and that peak is what blows.
  Measured: 11,575 bytes compiles and runs; 15,670 bytes gives
  `Lua memory limit exceeded` in `main.lua` with `used 42761 / limit 98304`.
  `used < limit` there means the system allocator failed, not the quota, so
  raising `heap_kb` cannot help. `check.lua` fails above 13,000 bytes.
- `lua_used` is roughly `19000 + 2 x source bytes`. A 17 KB source left only
  16 KB of system heap free.
- `heap_kb=96` is required, not optional — this app does not fit in 48 KB.
- **Contacts carry no usable `received_unix`** on this firmware, so contact
  index order is the only ordering available.
- `badge_id` is a 23-character word slug like `moon-honey-opal-bloom`.
- Coordinates and RGB channels must be **integers**. Prefer `//` over
  `math.floor`: it is a VM opcode, not a C call.
- 320x240 screen, 512 native widgets, 64 KiB `main.lua`, 48 KiB Share bundle.
- No `pcall`, so every nil must be guarded by hand.
- LED indices are 1-based. Front view: 1 upper-left, 2 upper-right,
  3 middle-right, 4 bottom-right, 5 bottom-left, 6 middle-left.
