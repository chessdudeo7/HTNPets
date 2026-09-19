--[==[badge-app
slug=htn_bump_pets
name=Bump Pets
icon=BUMP
api=2
heap_kb=96
wake_lock=1
]==]

-- Bump Pets -- your pet is made of the people you have met.
-- Each Connect contact adds a coloured spot; your badge id picks the species
-- and the coat colour.  Everyone starts as an egg and hatches on their next
-- bump, however many contacts they already had.
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

-- Built in separate statements on purpose: one big nested constructor makes
-- the main chunk reserve a register per element, which pushed it to 26 slots
-- and into stack-safety territory. Each statement below peaks on its own.
local C = {SCAN = 200, SPOT = 8, BG = 0x0b0f14, TAU = 6.2831853}
C.CW = {1, 2, 3, 4, 5, 6}
C.AT = {1, 2, 3, 5, 7, 10, 14, 19, 25, 32, 40, 50}
-- spot placement as thousandths of body width / height
C.SX = {-230, 190, 20, -150, 265, -280, 110, -40}
C.SY = {-110, -180, 150, 205, 60, 85, -20, -240}
-- name, ear w, ear h, ear radius, ear spread, tail size
C.SP = {}
C.SP[1] = {"Bun",  11, 30,  5, 26,  9}
C.SP[2] = {"Cat",  17, 17,  4, 31,  7}
C.SP[3] = {"Bear", 19, 19, 10, 34,  6}
C.SP[4] = {"Fox",  19, 24,  4, 35, 13}
C.PARTS = {"body", "belly", "head", "earL", "earR", "eyeL"}
C.PART2 = {"eyeR", "nose", "tail", "footL", "footR"}

local S = {
  total = 0, roles = 0, stage = 0, spots = 0, fold = 0,
  newest = "", petname = "PET", species = 1,
  pr = 255, pg = 190, pb = 90,
  phase = 0, nextf = 0, celeb = 0, blink = false,
  led = true, lv = 170,
  seen = -1, dirty = false,
  -- hatch is the contact count the egg was armed at, stored on the first
  -- open. Everyone hatches on their NEXT bump, however many contacts they
  -- already had, so the beat works for a full address book too. egg is
  -- derived from it on every scan.
  hatch = -1, egg = true,
  -- cur is the spot the attribution cursor is on, 0 for none. nm is a ring
  -- of contact names parallel to R, so a spot can name its person.
  cur = 0, nm = {},
}

-- progress of the bounded work queue.  step 0 means ready.
local P = {step = 1, i = 1, fold = 7, hits = {}, made = false}

local W = {}   -- named widgets
local G = {}   -- spot widgets
local R = {}   -- ring of contact hashes
local L = {}   -- precomputed base layout, so draw() only adds the bob

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

local function pastel(r, g, b)
  return hex((r + 510) // 3, (g + 510) // 3, (b + 510) // 3)
end

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
  local slot = (P.i - 1) % C.SPOT + 1
  R[slot] = h
  -- Only the ring's worth of names is kept, truncated. Retaining every
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

-- Sizes and base positions, computed once per rebuild so that draw() only
-- has to add the bob offset.
local function meta()
  S.fold = P.fold
  S.stage = stage_of(S.total)
  -- Arm the egg at whatever count this badge already has, once, on the first
  -- open. A badge with forty contacts still gets to watch it hatch.
  if S.hatch < 0 then
    S.hatch = S.total
    S.dirty = true
  end
  S.egg = S.total <= S.hatch
  local n = S.total
  if n > C.SPOT then n = C.SPOT end
  if S.egg then n = 0 end
  S.spots = n

  -- Coat colour comes from the people you met, so it shifts as you meet more.
  -- Species does not: it is set once from the badge id, in step 2.
  if S.total > 0 then
    S.pr, S.pg, S.pb = hue(S.fold % 360)
  else
    S.pr, S.pg, S.pb = 255, 190, 90
  end

  local hd = 30 + S.stage * 3          -- head diameter
  local bw = hd + 16                   -- body width
  local bh = hd + 4                    -- body height
  L.hd, L.bw, L.bh = hd, bw, bh

  local cy = 150 - bh // 2             -- body centre, feet sit near y=150
  L.bx = 160 - bw // 2
  L.by = cy - bh // 2
  L.hx = 160 - hd // 2
  L.hy = L.by - hd + hd // 4           -- head overlaps the body a little

  local sp = C.SP[S.species]
  L.ew, L.eh, L.er = sp[2], sp[3], sp[4]
  local spread = sp[5] * hd // 100
  L.elx = 160 - spread - L.ew // 2
  L.erx = 160 + spread - L.ew // 2
  L.ey = L.hy - L.eh + L.eh // 3

  L.ed = 6 + S.stage // 3              -- eye diameter
  L.elex = 160 - hd // 4 - L.ed // 2
  L.erex = 160 + hd // 4 - L.ed // 2
  L.eyy = L.hy + hd // 2 - L.ed // 2
  L.nw = 5 + S.stage // 4
  L.nx = 160 - L.nw // 2
  L.ny = L.eyy + L.ed + 2

  L.td = sp[6] * hd // 34
  L.tx = 160 + bw // 2 - L.td // 3
  L.ty = cy - L.td // 2
  L.fd = 10 + S.stage // 2
  L.flx = 160 - bw // 4 - L.fd // 2
  L.frx = 160 + bw // 4 - L.fd // 2
  L.fy = cy + bh // 2 - L.fd // 2
  L.blx = 160 - bw // 4
  L.bly = cy + bh // 6
  L.blw, L.blh = bw // 2, bh // 2
end

-- One function, three branches: three separate locals would each cost a
-- main-chunk slot, and the main chunk is the tightest budget in the file.
local function dress(part)
  local body = hex(S.pr, S.pg, S.pb)
  local soft = pastel(S.pr, S.pg, S.pb)
  if part == 1 then
    W.body:set_size(L.bw, L.bh)
    W.body:style({bg_color = body, radius = L.bh // 2, border_width = 0})
    W.belly:set_size(L.blw, L.blh)
    W.belly:style({bg_color = soft, radius = L.blh // 2, border_width = 0})
    W.head:set_size(L.hd, L.hd)
    W.head:style({bg_color = body, radius = L.hd // 2, border_width = 0})
    W.tail:set_size(L.td, L.td)
    W.tail:style({bg_color = body, radius = L.td // 2, border_width = 0})
  elseif part == 2 then
    W.earL:set_size(L.ew, L.eh)
    W.earL:style({bg_color = body, radius = L.er, border_width = 0})
    W.earR:set_size(L.ew, L.eh)
    W.earR:style({bg_color = body, radius = L.er, border_width = 0})
    W.eyeL:set_size(L.ed, L.ed)
    W.eyeL:style({bg_color = 0x14141c, radius = L.ed // 2, border_width = 0})
    W.eyeR:set_size(L.ed, L.ed)
    W.eyeR:style({bg_color = 0x14141c, radius = L.ed // 2, border_width = 0})
  else
    W.nose:set_size(L.nw, L.nw)
    W.nose:style({bg_color = 0xff9aab, radius = L.nw // 2, border_width = 0})
    W.footL:set_size(L.fd, L.fd)
    W.footL:style({bg_color = soft, radius = L.fd // 2, border_width = 0})
    W.footR:set_size(L.fd, L.fd)
    W.footR:style({bg_color = soft, radius = L.fd // 2, border_width = 0})
  end
end

-- style spots lo..hi, at most four per call
local function style_spot(lo, hi)
  local d = 7 + S.stage // 3
  for i = lo, hi do
    if i <= S.spots then
      local h = R[(S.total - S.spots + i - 1) % C.SPOT + 1] or 0
      G[i]:set_size(d, d)
      G[i]:style({radius = d // 2, border_width = 0,
                  bg_color = hex(hue(h % 360))})
      G[i]:set_pos(160 + C.SX[i] * L.bw // 1000 - d // 2,
                   L.by + L.bh // 2 + C.SY[i] * L.bh // 1000 - d // 2)
      G[i]:hidden(false)
    else
      G[i]:hidden(true)
    end
  end
end

-- The one line under the pet. Three states, so no caller duplicates these
-- strings: egg, a picked spot, or the default summary.
local function stat_line()
  if S.egg then
    if S.total > 0 then
      return S.total .. " friends waiting.  Bump one to hatch."
    end
    return "Open Connect and bump a badge to hatch"
  end
  if S.cur > 0 then
    local slot = (S.total - S.spots + S.cur - 1) % C.SPOT + 1
    return "#" .. (S.total - S.spots + S.cur) .. "  " .. (S.nm[slot] or "?")
  end
  return "friends " .. S.total .. "    roles " .. S.roles ..
         "    stage " .. S.stage
end

local function finish()
  W.egg:hidden(not S.egg)
  for i = 1, #C.PARTS do W[C.PARTS[i]]:hidden(S.egg) end
  for i = 1, #C.PART2 do W[C.PART2[i]]:hidden(S.egg) end
  W.prog:hidden(S.egg)
  if S.egg then
    W.title:set_text(S.petname .. "  the  egg")
  else
    W.title:set_text(S.petname .. "  the  " .. C.SP[S.species][1])
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

-- Attribution. Left/Right walk the coat spots; the picked one takes a white
-- outline and the line underneath names the contact it was made from. This is
-- what makes the pet a portrait rather than a progress bar.
local function pick(d)
  if S.egg or S.spots == 0 then return end
  local old = S.cur
  local c = old + d
  if c > S.spots then c = 0 elseif c < 0 then c = S.spots end
  S.cur = c
  if old > 0 and old <= S.spots then
    G[old]:style({border_width = 0})
  end
  if c > 0 then
    G[c]:style({border_color = 0xffffff, border_width = 2})
  end
  W.stat:set_text(stat_line())
end

local function draw(now)
  if S.egg then
    W.egg:set_pos(126, 52 + 6 * breath(now, 2600) // 100)
    return
  end
  -- gentle bob; ears and head lag by half a beat so it reads as breathing
  local b = breath(now, 2400)
  local dy = (b - 50) * 5 // 100
  local hdy = (breath(now + 300, 2400) - 50) * 6 // 100

  W.body:set_pos(L.bx, L.by + dy)
  W.belly:set_pos(L.blx, L.bly + dy)
  W.head:set_pos(L.hx, L.hy + hdy)
  W.earL:set_pos(L.elx, L.ey + hdy)
  W.earR:set_pos(L.erx, L.ey + hdy)
  W.eyeL:set_pos(L.elex, L.eyy + hdy)
  W.eyeR:set_pos(L.erex, L.eyy + hdy)
  W.nose:set_pos(L.nx, L.ny + hdy)
  W.tail:set_pos(L.tx, L.ty + dy)
  W.footL:set_pos(L.flx, L.fy)
  W.footR:set_pos(L.frx, L.fy)

  local shut = (now % 3600) < 130
  if shut ~= S.blink then
    S.blink = shut
    local h = L.ed
    if shut then h = 2 end
    W.eyeL:set_size(L.ed, h)
    W.eyeR:set_size(L.ed, h)
  end
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
    -- "come bump me" signal. All six, breathing 35..100% of brightness.
    -- Two leds at 15..50% read as off once the firmware curve is applied.
    local q = lv * (3500 + 65 * breath(now, 3000)) // 10000
    for i = 1, 6 do
      badge.led.set(C.CW[i], q, dim(180, q), dim(70, q))
    end
  else
    -- Coat 20..45%, with one travelling highlight at full brightness. Below
    -- about 20% the coat reads as black and only the highlight is visible.
    local q = lv * (2000 + 25 * breath(now, 2400)) // 10000
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
      -- Species is YOURS and never changes. Deriving it from the contact
      -- fold instead would turn you into a different animal every time you
      -- met someone, which is no way to get attached to a pet. Sampled from
      -- both ends of the id because word slugs share their separators.
      local a, b, d, e = string.byte(id, 1, 4)
      local f, g = string.byte(id, #id - 1, #id)
      S.species = ((a or 1) * 7 + (b or 2) * 13 + (d or 3) * 31
                   + (e or 5) * 57 + (f or 7) * 91 + (g or 11)) % 4 + 1
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
  elseif s == 5 then
    W.body = badge.ui.box(W.bg, 20, 20)
    W.belly = badge.ui.box(W.bg, 10, 10)
    W.tail = badge.ui.box(W.bg, 8, 8)
    W.head = badge.ui.box(W.bg, 20, 20)
    P.step = 6
  elseif s == 6 then
    W.earL = badge.ui.box(W.bg, 8, 8)
    W.earR = badge.ui.box(W.bg, 8, 8)
    W.eyeL = badge.ui.box(W.bg, 6, 6)
    W.eyeR = badge.ui.box(W.bg, 6, 6)
    P.step = 7
  elseif s == 7 then
    W.nose = badge.ui.box(W.bg, 5, 5)
    W.footL = badge.ui.box(W.bg, 8, 8)
    W.footR = badge.ui.box(W.bg, 8, 8)
    W.stat = badge.ui.label(W.bg, "")
    P.step = 8
  elseif s == 8 or s == 9 then
    local base = (s - 8) * 4
    for i = base + 1, base + 4 do
      G[i] = badge.ui.box(W.bg, 6, 6)
      G[i]:hidden(true)
    end
    P.step = s + 1
  elseif s == 10 then
    W.stat:style({text_font = 16, text_color = 0xc8d6e2})
    W.stat:align("top_mid", 0, 168)
    W.prog = badge.ui.bar(W.bg, 0, 100, 0)
    W.prog:set_size(236, 8)
    P.step = 11
  elseif s == 11 then
    W.prog:set_pos(42, 196)
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
    dress(s - 20)
    P.step = s + 1
  elseif s == 24 or s == 25 then
    style_spot((s - 24) * 4 + 1, (s - 24) * 4 + 4)
    P.step = s + 1
  elseif s == 26 then
    finish()
    P.step = 27
  else
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
