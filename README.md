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
It is complete and passes the headless harness, but at 15,670 bytes it is
over the compile-memory ceiling and dies in `main.lua` on the badge. Finish
it by getting it under ~12 KB, not by raising `heap_kb`.

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

Lint, Lua syntax, the value-stack slot budget, and a headless run of the real
app against a mock badge API at 0, 1, 5, 12, 40 and 200 contacts. Exits
non-zero on failure. If this fails, pushing will fail.

Needs Lua 5.4 (`winget install DEVCOM.Lua`), installed to
`%LOCALAPPDATA%\Programs\Lua\bin`. `check.ps1` locates it even when `lua` is
not on PATH — a terminal opened before the install keeps a stale PATH, and in
VS Code a new terminal tab inherits it too, so only restarting VS Code fixes
that. To patch the current session instead:

```powershell
$env:Path += ";$env:LOCALAPPDATA\Programs\Lua\bin"
```

## Pushing to a badge

Copy the app to the clipboard:

```powershell
Get-Content -Raw apps\bump_pets.lua | Set-Clipboard
```

```bash
cat apps/bump_pets.lua | clip
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
