--[==[badge-app
slug=htn_bump_pets
name=Bump Pets
icon=BUMP
api=2
heap_kb=96
wake_lock=1
]==]

-- Bump Pets -- your pet is made of the people you have met.
-- Every Connect contact adds a body segment coloured from their badge id.
-- Everyone starts as an egg and hatches on their next bump, however many
-- contacts they already had.  Left/Right name the person behind a segment.
-- L/R who is who   A rescan   B lights   Up/Dn brightness   HOME exit
--
-- READ BEFORE EDITING.  This badge raises "Lua stack safety limit reached"
-- when one callback does too much.  The vendor guide's remedy for that exact
-- message is "use an explicit bounded work queue", so on_enter does almost
-- nothing: it draws a loading label and returns.  All real work happens one
-- small step per on_tick, driven by P.step.  ONE contact is hashed per tick;
-- at most FOUR widgets are created or styled per tick.
--
-- Do not move work back into on_enter.  Do not wrap string.byte in a loop.
-- Keep state in these tables, not in file-level locals: each local costs a
-- main-chunk slot and an upvalue in every function that reads it.
-- Verify with:  .\check.ps1

local C = {
  SCAN = 200,
  SEG = 12,
  BG = 0x0b0f14,
  TAU = 6.2831853,
  CW = {1, 2, 3, 4, 5, 6},
  AT = {1, 2, 3, 5, 7, 10, 14, 19, 25, 32, 40, 50},
}

local S = {
  total = 0, roles = 0, stage = 0, segn = 0, fold = 0,
  newest = "", petname = "PET",
  pr = 255, pg = 190, pb = 90,
  phase = 0, amp = 10, gap = 20,
  nextf = 0, celeb = 0,
  led = true, lv = 170,
  seen = -1, dirty = false,
  -- hatch is the contact count the egg was armed at, stored on first open.
  -- Everyone starts as an egg and hatches on their NEXT bump, however many
  -- contacts they already had.  egg is derived from it every scan.
  hatch = -1, egg = true, cur = 0,
  nm = {},   -- ring of contact names, parallel to R (attribution)
}

-- progress of the bounded work queue.  step 0 means ready.
local P = {step = 1, i = 1, fold = 7, hits = {}, made = false}

local W = {}   -- named widgets
local G = {}   -- body segment widgets
local R = {}   -- ring of contact hashes; S.nm holds the names, in step
local D = {}   -- segment diameters

-- The ring slot for segment j is
--   (S.total - S.segn + j - 1) % C.SEG + 1
-- written out at both call sites rather than given a helper: a file-level
-- local costs a main-chunk slot, and this app is two slots under the limit.

local function hue(x)
  x = x % 360
  local s = x // 60
  local u = (200 * (x - s * 60)) // 60 + 55
  local d = 310 - u
  if s == 0 then return 255, u, 55 end
  if s == 1 then return d, 255, 55 end
  if s == 2 then return 55, 255, u end
  if s == 3 then return 55, d, 255 end
  if s == 4 then return u, 55, 255 end
  return 255, 55, d
end

local function hex(r, g, b) return r * 65536 + g * 256 + b end

local function dim(c, lv)
  local v = c * lv // 255
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

-- 0..100, integer: floats would reach set_pos and led.set, which want ints.
local function breath(now, p)
  local v = (now % p) * 200 // p
  if v > 100 then v = 200 - v end
  return v
end

local function stage_of(n)
  local s = 0
  for i = 1, #C.AT do
    if n >= C.AT[i] then s = i else break end
  end
  return s
end

local function seg_hash(j)
  return R[(S.total - S.segn + j - 1) % C.SEG + 1] or 0
end

-- ONE contact per call. Bytes in bulk, never string.byte in a loop.
local function scan_one()
  local c = badge.contacts.get(P.i)
  if not c then return false end
  S.total = P.i
  local k = tostring(c.role)
  if P.hits[k] == nil then
    S.roles = S.roles + 1
    P.hits[k] = true
  end
  local id = c.badge_id
  if type(id) ~= "string" then id = tostring(id) end
  local ln = #id
  local s2 = ln - 11
  if s2 < 1 then s2 = 1 end
  local h = 5381 + ln
  local a, b, d, e, f, g = string.byte(id, 1, 6)
  h = (h * 33 + (a or 1)) % 16777213
  h = (h * 33 + (b or 2)) % 16777213
  h = (h * 33 + (d or 3)) % 16777213
  h = (h * 33 + (e or 4)) % 16777213
  h = (h * 33 + (f or 5)) % 16777213
  h = (h * 33 + (g or 6)) % 16777213
  a, b, d, e, f, g = string.byte(id, 7, 12)
  h = (h * 33 + (a or 7)) % 16777213
  h = (h * 33 + (b or 8)) % 16777213
  h = (h * 33 + (d or 9)) % 16777213
  h = (h * 33 + (e or 10)) % 16777213
  h = (h * 33 + (f or 11)) % 16777213
  h = (h * 33 + (g or 12)) % 16777213
  a, b, d, e, f, g = string.byte(id, s2, s2 + 5)
  h = (h * 33 + (a or 13)) % 16777213
  h = (h * 33 + (b or 14)) % 16777213
  h = (h * 33 + (d or 15)) % 16777213
  h = (h * 33 + (e or 16)) % 16777213
  h = (h * 33 + (f or 17)) % 16777213
  h = (h * 33 + (g or 18)) % 16777213
  a, b, d, e, f, g = string.byte(id, s2 + 6, s2 + 11)
  h = (h * 33 + (a or 19)) % 16777213
  h = (h * 33 + (b or 20)) % 16777213
  h = (h * 33 + (d or 21)) % 16777213
  h = (h * 33 + (e or 22)) % 16777213
  h = (h * 33 + (f or 23)) % 16777213
  h = (h * 33 + (g or 24)) % 16777213
  P.fold = (P.fold * 33 + h) % 16777213
  local slot = (P.i - 1) % C.SEG + 1
  R[slot] = h
  -- Only the ring's worth of names is kept, truncated.  Retaining every
  -- contact record would be real money against the Lua heap.
  local nm = "?"
  if type(c.name) == "string" then
    nm = string.sub(c.name, 1, 16)
    S.newest = c.name
  end
  S.nm[slot] = nm
  P.i = P.i + 1
  return true
end

local function meta()
  S.fold = P.fold
  S.stage = stage_of(S.total)
  -- Arm the egg at whatever count this badge already has, once, on the first
  -- open.  A badge with forty contacts still gets to watch it hatch.
  if S.hatch < 0 then
    S.hatch = S.total
    S.dirty = true
  end
  S.egg = S.total <= S.hatch
  local n = S.total
  if n > C.SEG then n = C.SEG end
  if S.egg then n = 0 end
  S.segn = n
  if n > 0 then
    S.pr, S.pg, S.pb = hue(S.fold % 360)
  else
    S.pr, S.pg, S.pb = 255, 190, 90
  end
  local gp = 24
  if n > 0 then gp = 200 // n end
  if gp > 24 then gp = 24 end
  if gp < 12 then gp = 12 end
  S.gap = gp
  local a = 8 + S.stage
  if a > 16 then a = 16 end
  S.amp = a
end

-- style segments lo..hi, at most four per call
local function style_seg(lo, hi)
  for i = lo, hi do
    if i <= S.segn then
      local d = 12 + 14 * i // S.segn
      D[i] = d
      G[i]:set_size(d, d)
      G[i]:style({radius = d // 2, border_width = 0,
                  bg_color = hex(hue(seg_hash(i) % 360))})
      G[i]:hidden(false)
    else
      G[i]:hidden(true)
    end
  end
end

-- The one line under the pet.  Three states, so the callers never duplicate
-- these strings: egg, a picked segment, or the default summary.
local function stat_line()
  if S.egg then
    if S.total > 0 then
      return S.total .. " friends waiting.  Bump one to hatch."
    end
    return "Open Connect and bump a badge to hatch"
  end
  if S.cur > 0 then
    local slot = (S.total - S.segn + S.cur - 1) % C.SEG + 1
    return "#" .. (S.total - S.segn + S.cur) .. "  " .. (S.nm[slot] or "?")
  end
  return "friends " .. S.total .. "    roles " .. S.roles
end

local function finish()
  W.egg:hidden(not S.egg)
  W.head:hidden(S.egg)
  W.e1:hidden(S.egg)
  W.e2:hidden(S.egg)
  W.prog:hidden(S.egg)
  W.head:style({bg_color = hex(S.pr, S.pg, S.pb), radius = 17,
                border_width = 0})
  if S.egg then
    W.title:set_text(S.petname .. "  -  egg")
  else
    W.title:set_text(S.petname .. "  -  stage " .. S.stage)
  end
  W.stat:set_text(stat_line())
  local lo = C.AT[S.stage] or 0
  local hi = C.AT[S.stage + 1]
  local p = 100
  if hi and hi > lo then p = (S.total - lo) * 100 // (hi - lo) end
  if p < 0 then p = 0 end
  if p > 100 then p = 100 end
  W.prog:set_value(p)
end

-- Attribution.  Left/Right walk the segments; the picked one gets a white
-- outline and the line underneath names the person it was made from.  This is
-- what makes the pet a portrait rather than a progress bar, so it is worth its
-- two style calls.  Cursor 0 means nothing picked.
local function pick(d)
  if S.egg or S.segn == 0 then return end
  local old = S.cur
  local c = old + d
  if c > S.segn then c = 0 elseif c < 0 then c = S.segn end
  S.cur = c
  if old > 0 and old <= S.segn then
    G[old]:style({border_width = 0})
  end
  if c > 0 then
    G[c]:style({border_color = 0xffffff, border_width = 3})
  end
  W.stat:set_text(stat_line())
end

local function celebrate(now)
  if S.seen >= 0 and S.total > S.seen then
    if S.seen <= S.hatch and not S.egg then
      W.banner:set_text("HATCHED")
    elseif S.stage > stage_of(S.seen) then
      W.banner:set_text("EVOLVED   stage " .. S.stage)
    else
      W.banner:set_text("NEW FRIEND   " .. string.sub(S.newest, 1, 14))
    end
    W.banner:hidden(false)
    S.celeb = now + 2600
  end
  if S.seen ~= S.total then
    S.seen = S.total
    S.dirty = true
  end
end

local function draw(now)
  if S.egg then
    W.egg:set_pos(126, 52 + 6 * breath(now, 2600) // 100)
    return
  end
  local n = S.segn
  local gp = S.gap
  local x0 = 160 - (n * gp + 34) // 2
  for i = 1, n do
    local d = D[i]
    local y = 96 + math.floor(S.amp * math.sin(S.phase + i * 0.55))
    G[i]:set_pos(x0 + (i - 1) * gp + 10 - d // 2, y - d // 2)
  end
  local hy = 96 + math.floor(S.amp * math.sin(S.phase + (n + 1) * 0.55))
  local hx = x0 + n * gp + 14
  W.head:set_pos(hx - 17, hy - 17)
  W.e1:set_pos(hx - 3, hy - 8)
  W.e2:set_pos(hx + 7, hy - 8)
end

local function leds(now)
  badge.led.clear()
  if not S.led then
    badge.led.show()
    return
  end
  local lv = S.lv
  if S.celeb > now then
    local st = now // 80 % 6
    for i = 1, 6 do
      local q = lv - ((i - 1 - st) % 6) * 34
      if q < 0 then q = 0 end
      local r, g, b = hue(now // 4 + i * 60)
      badge.led.set(C.CW[i], dim(r, q), dim(g, q), dim(b, q))
    end
  elseif S.egg then
    -- The egg is the front door: every badge starts here, and it is the
    -- "come bump me" signal.  All six, breathing 35..100% of brightness.
    -- Two leds at 15..50% read as off once the firmware curve is applied.
    local q = lv * (3500 + 65 * breath(now, 3000)) // 10000
    for i = 1, 6 do
      badge.led.set(C.CW[i], q, dim(180, q), dim(70, q))
    end
  else
    -- Body 20..45%, with one travelling highlight at full brightness. Below
    -- about 20% the body reads as black and only the highlight is visible.
    local q = lv * (2000 + 25 * breath(now, 2600)) // 10000
    for i = 1, 6 do
      badge.led.set(C.CW[i], dim(S.pr, q), dim(S.pg, q), dim(S.pb, q))
    end
    local tr = 900 - S.stage * 40
    if tr < 260 then tr = 260 end
    badge.led.set(C.CW[now // tr % 6 + 1],
                  dim(S.pr, lv), dim(S.pg, lv), dim(S.pb, lv))
  end
  badge.led.show()
end

-- ONE bounded unit of work. Never chain two steps in a single tick.
local function step(now)
  local s = P.step
  if s == 1 then
    S.led = badge.store.get_int("led_on", 1) ~= 0
    S.lv = badge.store.get_int("led_lv", 170)
    S.seen = badge.store.get_int("seen", -1)
    S.hatch = badge.store.get_int("hatch", -1)
    P.step = 2
  elseif s == 2 then
    local id = badge.me.badge_id()
    if type(id) == "string" then
      S.petname = string.upper(string.match(id, "^[^-]+") or id)
    end
    P.step = 3
  elseif s == 3 then
    if P.i > C.SCAN or not scan_one() then
      if P.made then P.step = 20 else P.step = 4 end
    end
  elseif s == 4 then
    W.title = badge.ui.label(W.bg, "")
    W.title:style({text_font = 20})
    W.title:align("top_mid", 0, 8)
    W.egg = badge.ui.box(W.bg, 68, 86)
    W.egg:style({bg_color = 0xf0e6d2, radius = 34, border_width = 0})
    P.step = 5
  elseif s >= 5 and s <= 7 then
    local base = (s - 5) * 4
    for i = base + 1, base + 4 do
      G[i] = badge.ui.box(W.bg, 20, 20)
      G[i]:hidden(true)
    end
    P.step = s + 1
  elseif s == 8 then
    W.head = badge.ui.box(W.bg, 34, 34)
    W.e1 = badge.ui.box(W.bg, 6, 6)
    W.e2 = badge.ui.box(W.bg, 6, 6)
    P.step = 9
  elseif s == 9 then
    W.e1:style({bg_color = C.BG, radius = 3, border_width = 0})
    W.e2:style({bg_color = C.BG, radius = 3, border_width = 0})
    W.stat = badge.ui.label(W.bg, "")
    W.stat:style({text_font = 16, text_color = 0xc8d6e2})
    P.step = 10
  elseif s == 10 then
    W.stat:align("top_mid", 0, 168)
    W.prog = badge.ui.bar(W.bg, 0, 100, 0)
    W.prog:set_size(236, 8)
    W.prog:set_pos(42, 196)
    P.step = 11
  elseif s == 11 then
    W.prog:style({bg_color = 0x1d2733, radius = 4})
    W.banner = badge.ui.label(W.bg, "")
    W.banner:style({text_font = 18, text_color = 0xffd45e})
    P.step = 12
  elseif s == 12 then
    W.banner:align("top_mid", 0, 38)
    W.banner:hidden(true)
    W.hint = badge.ui.label(W.bg, "L/R who is who   A rescan   B lights")
    P.step = 13
  elseif s == 13 then
    W.hint:style({text_font = 14, text_color = 0x5d6f80})
    W.hint:align("bottom_mid", 0, -10)
    W.boot:hidden(true)
    P.made = true
    P.step = 20
  elseif s == 20 then
    meta()
    P.step = 21
  elseif s >= 21 and s <= 23 then
    style_seg((s - 21) * 4 + 1, (s - 21) * 4 + 4)
    P.step = s + 1
  elseif s == 24 then
    finish()
    P.step = 25
  else
    celebrate(now)
    S.nextf = now
    P.step = 0
  end
end

function on_enter(root)
  W.bg = badge.ui.box(root, 320, 240)
  W.bg:set_pos(0, 0)
  W.bg:style({bg_color = C.BG, border_width = 0, radius = 0})
  W.boot = badge.ui.label(W.bg, "waking up...")
  W.boot:style({text_font = 20, text_color = 0x5d6f80})
  W.boot:align("center", 0, 0)
end

function on_tick()
  local now = badge.sys.ms()
  if P.step > 0 then
    step(now)
    return
  end
  if now < S.nextf then return end
  S.nextf = now + 50
  if S.celeb > 0 and now >= S.celeb then
    W.banner:hidden(true)
    S.celeb = 0
  end
  S.phase = S.phase + 0.10
  if S.phase > C.TAU then S.phase = S.phase - C.TAU end
  draw(now)
  leds(now)
end

function on_button(button, kind)
  if kind ~= badge.input.KIND.PRESSED then return end
  if P.step > 0 then return end
  local B = badge.input.BUTTON
  if button == B.A then
    P.i, P.fold, P.hits = 1, 7, {}
    S.total, S.roles, S.cur = 0, 0, 0
    P.step = 3
    return
  elseif button == B.LEFT then
    pick(-1)
    return
  elseif button == B.RIGHT then
    pick(1)
    return
  elseif button == B.B then
    S.led = not S.led
    S.dirty = true
  elseif button == B.UP then
    S.lv = math.min(255, S.lv + 24)
    S.dirty = true
  elseif button == B.DOWN then
    S.lv = math.max(24, S.lv - 24)
    S.dirty = true
  else
    return
  end
  leds(badge.sys.ms())
end

function on_exit()
  badge.led.clear()
  badge.led.show()
  if S.dirty then
    badge.store.set_int("seen", S.seen)
    badge.store.set_int("hatch", S.hatch)
    badge.store.set_int("led_on", S.led and 1 or 0)
    badge.store.set_int("led_lv", S.lv)
  end
end
