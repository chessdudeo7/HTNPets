--[==[badge-app
slug=htn_symbiote
name=Symbiote
icon=SYM
api=2
heap_kb=48
wake_lock=1
]==]

-- Symbiote -- your pet is made of the people you have met.
-- Bump badges with the built-in Connect app; every contact adds a segment
-- coloured from that badge ID.  Rare roles grow spikes.
--
-- A      toggle pet / stats view
-- B      LEDs on / off
-- Up/Dn  LED brightness
-- Start  rescan contacts
-- HOME   exit (saves settings)

local MAX_SCAN = 200
local MAX_SEG  = 12
local MAX_SPK  = 4
local CW = {1, 2, 3, 4, 5, 6}                       -- clockwise from upper left
local STAGE_AT = {1, 2, 3, 5, 7, 10, 14, 19, 25, 32, 40, 50}
local SPECIES = {"Drifter", "Weaver", "Bridger", "Keystone"}
local SYL_A = {"ne", "ka", "or", "vu", "sel", "mar", "thi", "zo"}
local SYL_B = {"bbit", "lux", "ven", "dra", "mo", "ska", "ril", "phen"}
local BG = 0x0b0f14
local TAU = 6.2831853

-- derived state
local total, roles_n, rare_n, stage = 0, 0, 0, 0
local recent = {}
local seg_d, spk_seg, spk_n = {}, {}, 0
local seg_count = 0
local pet_r, pet_g, pet_b = 90, 200, 255
local me_r, me_g, me_b = 90, 200, 255
local pet_name, pet_species, newest, stats_text = "", "", "", ""

-- runtime state
local phase, amp, seg_sp = 0, 10, 20
local next_frame = 0
local led_on, led_level = true, 170
local celebrate_until, banner_on = 0, false
local flat_since, asleep, eyes_shut = 0, false, false
local dizzy_until = 0
local view = 1
local seen_count, dirty_store = -1, false

-- widgets
local bg, name_lbl, sp_lbl, stat_lbl, hint, banner, prog, panel, egg
local head, eye1, eye2
local seg, spk = {}, {}

-- ---------------------------------------------------------------- helpers

local function hash_str(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 2147483647
  end
  return h
end

local function hue_rgb(h)
  h = h % 360
  local s = math.floor(h / 60)
  local f = (h - s * 60) / 60
  local up = math.floor(200 * f) + 55
  local dn = math.floor(200 * (1 - f)) + 55
  if s == 0 then return 255, up, 55 end
  if s == 1 then return dn, 255, 55 end
  if s == 2 then return 55, 255, up end
  if s == 3 then return 55, dn, 255 end
  if s == 4 then return up, 55, 255 end
  return 255, 55, dn
end

local function hex(r, g, b) return r * 65536 + g * 256 + b end

local function dim(c, lv)
  local v = math.floor(c * lv / 255)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function breath(now, period)
  local p = (now % period) / period * 2
  if p > 1 then p = 2 - p end
  return p
end

local function stage_of(n)
  local s = 0
  for i = 1, #STAGE_AT do
    if n >= STAGE_AT[i] then s = i else break end
  end
  return s
end

local function name_for(id)
  local h = hash_str(id)
  local a = SYL_A[(h % #SYL_A) + 1]
  local b = SYL_B[(math.floor(h / 8) % #SYL_B) + 1]
  return string.upper(a .. b)
end

-- ---------------------------------------------------------------- contacts

local function push_recent(rec)
  local n = #recent
  if n < MAX_SEG then
    recent[n + 1] = rec
    return
  end
  local mi, mv = 1, recent[1].sv
  for i = 2, n do
    if recent[i].sv < mv then mi, mv = i, recent[i].sv end
  end
  if rec.sv > mv then recent[mi] = rec end
end

-- One pass over the address book.  Nothing is retained per contact except
-- the bounded recent buffer, so a 200-entry book stays cheap on the heap.
local function scan()
  total, roles_n, rare_n = 0, 0, 0
  recent = {}
  local hits, order = {}, {}
  local fold = 7
  local i = 1
  while i <= MAX_SCAN do
    local c = badge.contacts.get(i)
    if not c then break end
    total = i

    local key = tostring(c.role)
    if hits[key] == nil then
      roles_n = roles_n + 1
      order[roles_n] = key
      hits[key] = 0
    end
    hits[key] = hits[key] + 1

    local id = c.badge_id
    if type(id) ~= "string" then id = tostring(id) end
    local ch = hash_str(id)
    fold = (fold * 33 + ch) % 2147483647

    -- Sort key: a real timestamp when we have one, otherwise the index.
    -- Timestamps are huge, so known-recent always beats unknown.
    local t = c.received_unix
    local sv = i
    if type(t) == "number" and t > 1000000000 then sv = t end

    local nm = c.name
    if type(nm) ~= "string" then nm = "?" end

    push_recent({sv = sv, h = ch, role = key, name = nm})
    i = i + 1
  end

  table.sort(recent, function(a, b) return a.sv < b.sv end)

  -- A role is rare when it is under a quarter of your book.
  for k = 1, #recent do
    local rc = hits[recent[k].role] or 0
    recent[k].rare = (total >= 4 and rc * 4 <= total)
  end
  for k = 1, roles_n do
    local key = order[k]
    if total >= 4 and hits[key] * 4 <= total then
      rare_n = rare_n + hits[key]
    end
  end

  if #recent > 0 then newest = recent[#recent].name else newest = "" end
  return fold
end

-- ---------------------------------------------------------------- creature

local function apply_creature(fold)
  stage = stage_of(total)
  seg_count = #recent
  if seg_count > MAX_SEG then seg_count = MAX_SEG end

  pet_r, pet_g, pet_b = hue_rgb(fold % 360)

  local si = roles_n
  if si < 1 then si = 1 end
  if si > #SPECIES then si = #SPECIES end
  pet_species = SPECIES[si]

  seg_sp = 24
  if seg_count > 0 then seg_sp = math.floor(200 / seg_count) end
  if seg_sp > 24 then seg_sp = 24 end
  if seg_sp < 12 then seg_sp = 12 end

  amp = 8 + stage
  if amp > 16 then amp = 16 end

  spk_n = 0
  for i = 1, MAX_SEG do
    if i <= seg_count then
      local d = 12 + math.floor(14 * i / seg_count)
      seg_d[i] = d
      seg[i]:set_size(d, d)
      seg[i]:style({radius = math.floor(d / 2), border_width = 0,
                    bg_color = hex(hue_rgb(recent[i].h % 360))})
      if recent[i].rare and spk_n < MAX_SPK then
        spk_n = spk_n + 1
        spk_seg[spk_n] = i
        spk[spk_n]:style({line_color = 0xffffff, line_width = 3})
      end
    end
  end

  head:style({bg_color = hex(me_r, me_g, me_b), radius = 17, border_width = 0})

  name_lbl:set_text(pet_name)
  name_lbl:style({text_color = hex(pet_r, pet_g, pet_b)})
  if stage > 0 then
    sp_lbl:set_text(pet_species)
    stat_lbl:set_text("friends " .. total .. "    roles " .. roles_n ..
                      "    stage " .. stage)
  else
    sp_lbl:set_text("unhatched")
    stat_lbl:set_text("Open Connect and bump a badge to hatch")
  end

  local lo = STAGE_AT[stage] or 0
  local hi = STAGE_AT[stage + 1]
  local pct = 100
  if hi then
    local span = hi - lo
    if span > 0 then pct = math.floor((total - lo) * 100 / span) end
  end
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  prog:set_value(pct)
  prog:style({bg_color = hex(dim(pet_r, 200), dim(pet_g, 200), dim(pet_b, 200))},
             "indicator")

  stats_text =
    "friends   " .. total ..
    "\nroles     " .. roles_n .. " distinct" ..
    "\nrare      " .. rare_n .. " meetings" ..
    "\nnewest    " .. string.sub(newest, 1, 16) ..
    "\nspecies   " .. (stage > 0 and pet_species or "-") ..
    "\nstage     " .. stage .. " of " .. #STAGE_AT ..
    "\nnext at   " .. (STAGE_AT[stage + 1] or total) .. " friends"
end

local function show_pet(on)
  local egg_on = on and stage == 0
  local body_on = on and stage > 0
  egg:hidden(not egg_on)
  head:hidden(not body_on)
  eye1:hidden(not body_on)
  eye2:hidden(not body_on)
  for i = 1, MAX_SEG do
    seg[i]:hidden(not (body_on and i <= seg_count))
  end
  for k = 1, MAX_SPK do
    spk[k]:hidden(not (body_on and k <= spk_n))
  end
end

local function set_view(v)
  view = v
  show_pet(v == 1)
  panel:hidden(v ~= 2)
  stat_lbl:hidden(v ~= 1)
  prog:hidden(v ~= 1)
  if v == 2 then panel:set_text(stats_text) end
end

-- ---------------------------------------------------------------- drawing

local function render_body(now)
  if view ~= 1 then return end
  local cy = 96

  if stage == 0 then
    local b = breath(now, 2600)
    egg:set_pos(126, 52 + math.floor(6 * b))
    return
  end

  local a = amp
  if dizzy_until > now then a = amp * 2 end
  local span = seg_count * seg_sp + 34
  local x0 = 160 - math.floor(span / 2)

  for i = 1, seg_count do
    local d = seg_d[i]
    local y = cy + math.floor(a * math.sin(phase + i * 0.55))
    local x = x0 + (i - 1) * seg_sp + 10
    seg[i]:set_pos(x - math.floor(d / 2), y - math.floor(d / 2))
  end

  for k = 1, spk_n do
    local i = spk_seg[k]
    local d = seg_d[i]
    local y = cy + math.floor(a * math.sin(phase + i * 0.55))
    local x = x0 + (i - 1) * seg_sp + 10
    spk[k]:set_pos(x - 2, y - math.floor(d / 2) - 13)
  end

  local hy = cy + math.floor(a * math.sin(phase + (seg_count + 1) * 0.55))
  local hx = x0 + seg_count * seg_sp + 14
  head:set_pos(hx - 17, hy - 17)
  local ey = hy - 8
  if eyes_shut then ey = hy - 5 end
  eye1:set_pos(hx - 3, ey)
  eye2:set_pos(hx + 7, ey)
end

local function render_leds(now)
  badge.led.clear()
  if not led_on then
    badge.led.show()
    return
  end

  if celebrate_until > now then
    local step = math.floor(now / 80) % 6
    for i = 1, 6 do
      local d = (i - 1 - step) % 6
      local lv = led_level - d * 34
      if lv < 0 then lv = 0 end
      local r, g, b = hue_rgb(math.floor(now / 4) + i * 60)
      badge.led.set(CW[i], dim(r, lv), dim(g, lv), dim(b, lv))
    end
  elseif stage == 0 then
    local lv = math.floor(led_level * (0.15 + 0.35 * breath(now, 3000)))
    badge.led.set(1, lv, dim(180, lv), dim(70, lv))
    badge.led.set(2, lv, dim(180, lv), dim(70, lv))
  else
    local base = math.floor(led_level * (0.10 + 0.20 * breath(now, 2600)))
    for i = 1, 6 do
      badge.led.set(CW[i], dim(pet_r, base), dim(pet_g, base), dim(pet_b, base))
    end
    local travel = 900 - stage * 40
    if travel < 260 then travel = 260 end
    local h = (math.floor(now / travel) % 6) + 1
    badge.led.set(CW[h], dim(pet_r, led_level), dim(pet_g, led_level),
                  dim(pet_b, led_level))
  end
  badge.led.show()
end

-- ---------------------------------------------------------------- lifecycle

function on_enter(root)
  led_on = badge.store.get_int("led_on", 1) ~= 0
  led_level = badge.store.get_int("led_lv", 170)
  if led_level < 24 then led_level = 24 end
  if led_level > 255 then led_level = 255 end
  seen_count = badge.store.get_int("seen", -1)

  if badge.me.provisioned() then
    local r, g, b = badge.me.color()
    if type(r) == "number" then me_r, me_g, me_b = r, g, b end
  end
  local my_id = badge.me.badge_id()
  if type(my_id) ~= "string" then my_id = tostring(my_id or "egg") end
  pet_name = name_for(my_id)

  bg = badge.ui.box(root, 320, 240)
  bg:set_pos(0, 0)
  bg:style({bg_color = BG, border_width = 0, radius = 0})

  name_lbl = badge.ui.label(bg, "")
  name_lbl:style({text_font = 20})
  name_lbl:align("top_left", 12, 8)

  sp_lbl = badge.ui.label(bg, "")
  sp_lbl:style({text_font = 14, text_color = 0x7d92a6})
  sp_lbl:align("top_right", -12, 13)

  egg = badge.ui.box(bg, 68, 86)
  egg:style({bg_color = 0xf0e6d2, radius = 34, border_width = 2,
             border_color = 0xcbb894})
  egg:hidden(true)

  for k = 1, MAX_SPK do
    spk[k] = badge.ui.line(bg, {{0, 13}, {4, 0}})
    spk[k]:hidden(true)
  end
  for i = 1, MAX_SEG do
    seg[i] = badge.ui.box(bg, 20, 20)
    seg[i]:hidden(true)
  end
  head = badge.ui.box(bg, 34, 34)
  head:hidden(true)
  eye1 = badge.ui.box(bg, 6, 6)
  eye2 = badge.ui.box(bg, 6, 6)
  eye1:style({bg_color = BG, radius = 3, border_width = 0})
  eye2:style({bg_color = BG, radius = 3, border_width = 0})
  eye1:hidden(true)
  eye2:hidden(true)

  stat_lbl = badge.ui.label(bg, "")
  stat_lbl:style({text_font = 16, text_color = 0xc8d6e2})
  stat_lbl:align("top_mid", 0, 162)

  prog = badge.ui.bar(bg, 0, 100, 0)
  prog:set_size(236, 8)
  prog:set_pos(42, 190)
  prog:style({bg_color = 0x1d2733, radius = 4})

  panel = badge.ui.label(bg, "")
  panel:style({text_font = 16, text_align = "left", text_color = 0xc8d6e2})
  panel:align("center", 0, 6)
  panel:hidden(true)

  banner = badge.ui.label(bg, "")
  banner:style({text_font = 18, text_color = 0xffd45e})
  banner:align("top_mid", 0, 36)
  banner:hidden(true)

  hint = badge.ui.label(bg, "A stats   B lights   Up/Dn bright   Start rescan")
  hint:style({text_font = 14, text_color = 0x5d6f80})
  hint:align("bottom_mid", 0, -10)

  local fold = scan()
  apply_creature(fold)
  set_view(1)

  local now = badge.sys.ms()
  if seen_count >= 0 and total > seen_count then
    if stage > stage_of(seen_count) then
      banner:set_text("EVOLVED   stage " .. stage)
    else
      banner:set_text("NEW FRIEND   " .. string.sub(newest, 1, 14))
    end
    banner:hidden(false)
    banner_on = true
    celebrate_until = now + 2600
  end
  if seen_count ~= total then
    seen_count = total
    dirty_store = true
  end

  next_frame = now
  render_body(now)
  render_leds(now)
end

function on_tick()
  local now = badge.sys.ms()
  if now < next_frame then return end
  next_frame = now + 50

  if banner_on and now >= celebrate_until then
    banner:hidden(true)
    banner_on = false
  end

  if badge.sensor.tap() then
    dizzy_until = now + 400
    asleep, flat_since = false, 0
  end
  if badge.sensor.shake() then
    dizzy_until = now + 1200
    asleep, flat_since = false, 0
  end

  local o = badge.sensor.orientation()
  if o == "flat_up" then
    if flat_since == 0 then
      flat_since = now
    elseif now - flat_since > 4000 then
      asleep = true
    end
  else
    flat_since, asleep = 0, false
  end
  if asleep ~= eyes_shut then
    eyes_shut = asleep
    if asleep then
      eye1:set_size(6, 2)
      eye2:set_size(6, 2)
    else
      eye1:set_size(6, 6)
      eye2:set_size(6, 6)
    end
  end

  local sp = 0.10
  if asleep then sp = 0.03 end
  if dizzy_until > now then sp = 0.34 end
  phase = phase + sp
  if phase > TAU then phase = phase - TAU end

  render_body(now)
  render_leds(now)
end

function on_button(button, kind)
  if kind ~= badge.input.KIND.PRESSED then return end
  local B = badge.input.BUTTON
  if button == B.A then
    if view == 1 then set_view(2) else set_view(1) end
  elseif button == B.B then
    led_on = not led_on
    dirty_store = true
  elseif button == B.UP then
    led_level = math.min(255, led_level + 24)
    dirty_store = true
  elseif button == B.DOWN then
    led_level = math.max(24, led_level - 24)
    dirty_store = true
  elseif button == B.START then
    local fold = scan()
    apply_creature(fold)
    set_view(view)
    if seen_count ~= total then
      seen_count = total
      dirty_store = true
    end
  else
    return
  end
  local now = badge.sys.ms()
  render_body(now)
  render_leds(now)
end

function on_exit()
  badge.led.clear()
  badge.led.show()
  if dirty_store then
    badge.store.set_int("seen", seen_count)
    badge.store.set_int("led_on", led_on and 1 or 0)
    badge.store.set_int("led_lv", led_level)
  end
end
