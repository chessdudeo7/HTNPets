# HTNPets

Badge apps for Hack the North 2026. The repo is the source of truth; the
[Badge IDE](https://badge.hackthenorth.com/ide/) is only the flashing tool —
its workspace lives in browser localStorage, so nothing is safe there.

## Apps

| File | Slug | What |
| --- | --- | --- |
| `apps/symbiote.lua` | `htn_symbiote` | The pet. A creature built from your Connect contacts. |
| `apps/sym_probe.lua` | `sym_probe` | Read-only feasibility probe. Push this first. |

Each file is a complete app in the single-file format: the `--[==[badge-app`
header becomes `manifest.cfg`, everything after `]==]` becomes `main.lua`.
Keep them single-file — the format only packages those two, so modules would
have to be maintained by hand in the IDE.

## Pushing to a badge

```bash
cat apps/symbiote.lua | clip
```

Then in the IDE: **Import app** → paste → check the slug → **Replace editor
files** → **Push** → open it on the badge with **A**.

Before the first push: badge off, USB **data** cable in, badge on *without*
holding Start, desktop Chrome or Edge, no other tab holding the serial port.
Pick **USB JTAG/serial debug unit** in the device picker.

- Code edits need **Push** and reopening the app.
- Manifest edits (`api`, `heap_kb`, `wake_lock`, `home_button`, `confirm_home`)
  need a **Reboot** — a rescan only refreshes name and icon.

## Lint

```bash
bash lint.sh apps/*.lua
```

Checks the manifest header, identifiers the badge sandbox removes (`pcall`,
`os`, `io`, `coroutine`, `load`, `setmetatable`), `api=1`-only factories,
non-ASCII bytes the bundled fonts cannot render, and the size caps. It also
runs `luac -p` for real syntax checking.

Lua 5.4.6 (`winget install DEVCOM.Lua`) installs to
`%LOCALAPPDATA%\Programs\Lua\bin`, which lint.sh falls back to when `luac`
is not yet on PATH. Syntax checking locally is worth it: the badge has no
`pcall`, so a typo is an error card rather than a stack trace.

## Constraints worth remembering

- 320x240 screen, 512 native widgets, 48 KiB Lua heap, 64 KiB `main.lua`.
- 48 KiB total for a Share bundle — over that and the app cannot spread.
- Budgets: 3000 ms `on_enter`, 250 ms shared `on_tick`, 1000 ms `on_button`,
  1000 ms `on_exit`. Aim for a few ms in tick.
- No `pcall`, so every nil has to be guarded by hand.
- LED indices are 1-based. Front view: 1 upper-left, 2 upper-right,
  3 middle-right, 4 bottom-right, 5 bottom-left, 6 middle-left.
