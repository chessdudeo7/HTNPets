# What the badge actually does

Everything here was measured on hardware during the event. It is written down
because most of it cost hours to find and none of it is in the vendor guide.

## The short version

- **A widget costs about 112 bytes of system heap. A source byte costs 1.4 to
  2.5.** Widgets are the expensive thing by a factor of about fifty.
- **Connect takes ~51 KB for BLE and does not release it.** After using it, no
  useful Lua app can start until the badge reboots.
- The failure is the **system allocator**, not the Lua quota. `used` is far
  below `limit` when it happens.
- **What runs out is the largest contiguous block**, so the same app and size
  both passes and fails depending on what ran before. **Reboot before judging
  any result.**
- **Run-to-run variance in free heap is about 900 bytes**, so a saving smaller
  than that cannot be measured by launching the app twice.

## The memory model

There are two numbers and they are not the same. `lua_used` is Lua's own
accounting. What actually runs out is **system heap**, which is larger,
because the allocator adds block headers, alignment and fragmentation.

`lua_used` is linear in source size, measured with probes:

| source bytes | predicted `lua_used` | measured |
| --- | --- | --- |
| 13,667 | 46,334 | 47,581 |
| 15,587 | 50,174 | 51,596 |

So `lua_used ~= 19000 + 2.09 * bytes`.

**But budget against system heap, not that.** Measured from the `free` delta
either side of launching the real app:

| source bytes | predicted `lua_used` | system heap consumed | ratio |
| --- | --- | --- | --- |
| 13,793 | 47,827 | 58,024 | 1.21 |
| 14,717 | 49,759 | 61,004 | 1.23 |

About 22% more than `lua_used`, because the allocator adds block headers,
alignment and fragmentation.

**The per-byte figure is not settled.** Comparing those two builds gives 2.55
bytes of heap per source byte. Measuring a 563-byte cut *within* one build gave
776 bytes of heap, a ratio of 1.4. Two points across different apps and one
delta within an app disagree, so treat anything between **1.4 and 2.5** as the
plausible range and do not plan around the precise number.

**What is settled: a widget costs about 112 bytes.** Measured against the
28-widget build (58,024 consumed) and the 148-widget one (71,448). That is
roughly fifty times what a source byte costs, so **widgets are the lever**.
Cutting 1,000 source bytes buys somewhere between 12 and 22 widgets; not
allocating 84 widgets you never draw buys 9,400 bytes outright.

**Run-to-run variance is about 900 bytes.** One measurement pair differed by
868 bytes of starting free heap purely from how fragmented the boot was. A
saving smaller than that cannot be confirmed by launching twice.

### Two bugs this model caused

**Sizing a feature from a guessed reserve.** The painting budgeted itself from
`free_heap - 14000`, on the assumption that a 14,717-byte app leaves about
24 KB free. It leaves 11,920. The budget went negative, clamped to zero, and
the app drew a creature in front of an empty sky. Anything that adapts to free
memory needs a **floor** and a **log line**, or it fails silently.

**Allocating widgets that are never drawn.** The painting created `C.MAXS`
stroke widgets and hid the ones it did not paint. Hiding a widget does not free
it. At 9 contacts that was 84 widgets and 9.4 KB held by invisible objects, and
it left the app running on 2.2 KB of system heap with a low-water mark of 532
bytes. That is why failures looked random for hours.

**Prototype count is a second budget.** Each Lua `Proto` carries a constant
array, upvalue descriptors, a code array and debug info. Two apps of the same
size differing only in function count:

| bytes | prototypes | `lua_used` | result |
| --- | --- | --- | --- |
| 13,750 | 137 | 60,864 | **fails** |
| 13,750 | 18 | 47,581 | loads |

13,283 bytes of Lua memory between them: about **112 bytes per prototype**.
Splitting logic into many small helpers is not free.

## Connect strands the heap

Opening Connect initialises BLE, which takes about 51 KB:

```
heap after exit Launcher:    free=77436  largest=63488
hal_radio: init_once:        free heap 77340 largest 63488
hal_radio: waiting for sync  free heap 26992
heap after enter Connect:    free=26100  largest=17408
heap after exit  Connect:    free=26100  largest=17408   <- nothing released
```

With 26,100 bytes free, the largest app that fits is about **3,400 source
bytes**. Nothing useful. Launching anything larger fails, and the error names
whichever allocation happened to run out first:

```
E script_app: [htn_bump_pets] main.lua: Lua memory limit exceeded
  (used 17938 / limit 98304, peak 18106)
```

`used` is 80 KB below the quota. The Lua limit is not what ran out.

In a worse state it fails even earlier, before reading the file at all:

```
E esp_littlefs: Unable to allocate FD
E script_app: [htn_bump_pets] main.lua: cannot open .../main.lua: Invalid argument
```

A one-line app fails identically there. **Size is not the variable.**

### The reboot that should fix it, and does not reliably

The firmware is supposed to reboot on the way out of a radio app, which does
restore everything:

```
app_reg: heap after exit Connect: free=18744 largest=10752
app_reg: reboot-exit connect
app_reboot: reboot to launcher focus=connect
...      heap after exit ?:       free=73668 largest=63488
```

That fired **once** across several attempts. Two later runs exiting Connect the
same way produced no `reboot-exit` line and no reclamation. The run that
rebooted had completed a contact exchange (`contacts_store: saved contact`);
the ones that did not had entered and left without bumping. That may or may not
be the trigger; it is not confirmed.

**Consequence for the demo.** The beat is "bump me, then open your pet", and
that path requires a reboot in between - about 1.4 seconds from `rst:` to
launcher. Design it in rather than discovering it at the judging table. The pet
is a pure function of the contacts book, so a reboot costs nothing.

## The ceiling is not a fixed number

| file bytes | prototypes | `lua_used` | free heap | result |
| --- | --- | --- | --- | --- |
| 11,575 | 21 | - | - | loads |
| 12,524 | 19 | - | - | loads |
| 13,750 | **137** | 60,864 | - | **fails** |
| 13,750 | 18 | 47,581 | 23,464 | loads |
| 15,670 | 19 | 51,596 | 18,920 | loads |
| 15,670 | 19 | - | - | **failed once**, fragmented heap |

The same size both passed and failed. What runs out is the **largest contiguous
block**, so it depends on heap state at launch, which depends on what ran
before. `check.lua` therefore sits below the highest pass rather than at it.

Other things that move it:

- **Installed apps cost registry memory.** Four probe apps - about 900 bytes -
  were enough to stop the real app loading. Deleting them fixed it.
- **Running any other app first costs ~6 KB of the largest block.** Straight
  after boot `largest` is 63,488; after one app it is 57,344, and that
  difference was once the whole margin.

## Measuring

```bash
lua tools/ceilingprobe.lua 13750 14500      # padded apps at exact sizes
```

Each probe gets its own slug so several can be installed at once. Push them,
then open each. It prints its own size and heap stats, or dies in `main.lua`.

Read `heap` in the IDE console, and treat `sys_largest` as the number that
matters, not `sys_free`. Read it **while the app is open** as well as before:
the two answer different questions, and the running number is the one that
says whether there is any margin.

**A probe perturbs what it measures**, in at least three ways that all produced
wrong answers here before being caught:

- Padding with many tiny functions measures prototype overhead, not size.
- Installing several probes costs registry memory; four were enough to stop the
  real app loading.
- Starting free heap varies by ~900 bytes between boots, which is larger than
  most savings worth making.

**An app can log its own view.** `badge.sys.stats().free_heap` read at runtime
is how the painting sizes itself, and printing that decision with
`badge.sys.log` is what turned "nine friends, zero strokes" from a mystery into
a one-line diagnosis.

## Smaller things

- **`received_unix` is unusable.** Contact index order is the only ordering
  available, so every time-derived feature is out.
- **`badge_id` is a 23-to-25 character word slug**, e.g. `moon-honey-opal-bloom`.
- **The value-stack limit is about 25 slots** per chunk and per function. Each
  file-level local costs a main-chunk slot and an upvalue in every function
  that reads it. Measure with `luac -l app.lua | grep slots`.
- **The brightness curve flattens small values.** Two LEDs at 15-50% of the
  setting read as off. Anything meant to be seen wants a peak around 60% or
  more; `test/mockbadge.lua` enforces a floor because this shipped once.
- **`[push] reload confirmed` means uploaded and rescanned**, not that the app
  ran. Read the badge screen and the console too.
- **Windows: `winget` on PATH is a 0-byte stub** that fails mid-pipeline. Use
  `& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"`.
