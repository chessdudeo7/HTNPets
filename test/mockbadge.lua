-- Headless harness: runs a badge app against a mock badge API and asserts the
-- things the real device enforces but a syntax check cannot -- integer
-- coordinates, integer RGB in 0..255, LED indices 1..6, widget count, and that
-- no lifecycle callback errors.
--
--   lua test/mockbadge.lua apps/bump_pets.lua [contacts]
--
-- This cannot reproduce ESP32 timing, LVGL allocation, or the value-stack
-- guard.  It catches logic and type bugs, which is most of what costs a push.

local app_path = arg[1] or "apps/bump_pets.lua"
local n_contacts = tonumber(arg[2]) or 12

local fails, widgets = {}, 0
local function check(ok, msg)
  if not ok then fails[#fails + 1] = msg end
end
local function int(v, what)
  check(math.type(v) == "integer", what .. " is not an integer: " .. tostring(v))
end

-- fake contact book, word-slug ids like the real badge issues
local W1 = {"brook", "maple", "frost", "ember", "river", "stone", "cedar",
            "amber", "north", "quiet", "swift", "moon", "honey", "opal"}
local W2 = {"frost", "star", "moss", "tide", "vale", "peak", "reed", "honey"}
local W3 = {"star", "summit", "ridge", "grove", "harbor", "opal", "cliff"}
local W4 = {"summit", "haven", "field", "crest", "trail", "bloom", "glen"}
local contacts = {}
for i = 1, n_contacts do
  contacts[i] = {
    name = "Person " .. i,
    role = (i % 4 == 0) and "Mentor" or "Hacker",
    badge_id = W1[i % #W1 + 1] .. "-" .. W2[i % #W2 + 1] .. "-" ..
               W3[i % #W3 + 1] .. "-" .. W4[i % #W4 + 1],
    received_unix = nil,          -- the real badge returns no usable stamps
  }
end

local STYLE_KEYS = {
  bg_color=1, bg_opa=1, color=1, opa=1, radius=1, border_color=1, border_opa=1,
  border_width=1, text_color=1, text_opa=1, text_font=1, text_align=1,
  arc_color=1, arc_opa=1, arc_width=1, line_color=1, line_opa=1, line_width=1,
  pad_all=1, pad_top=1, pad_bottom=1, pad_left=1, pad_right=1, pad_row=1,
  pad_column=1, shadow_color=1, shadow_opa=1, shadow_width=1, shadow_spread=1,
  shadow_offset_x=1, shadow_offset_y=1, flex_flow=1,
}

local Widget = {}
Widget.__index = Widget
local all = {}
local function new_widget(kind)
  widgets = widgets + 1
  check(widgets <= 512, "widget cap 512 exceeded")
  local w = setmetatable({kind = kind, shown = true, n = widgets}, Widget)
  all[#all + 1] = w
  return w
end
function Widget:set_pos(x, y)
  int(x, "set_pos x"); int(y, "set_pos y")
  self.x, self.y = x, y
  -- top-left must stay on a 320x240 screen, with a little slack
  check(x >= -12 and x <= 320, "set_pos x off screen: " .. tostring(x))
  check(y >= -12 and y <= 236, "set_pos y off screen: " .. tostring(y))
end
function Widget:set_size(w, h)
  int(w, "set_size w"); int(h, "set_size h")
  self.w, self.h = w, h
  check(w > 0 and h > 0, "set_size non-positive: " .. w .. "x" .. h)
  check(w <= 320 and h <= 240, "set_size larger than screen: " .. w .. "x" .. h)
end
function Widget:align(a, x, y)
  check(type(a) == "string", "align name")
  int(x, "align dx"); int(y, "align dy")
  -- Kept so the renderer can place labels, which never get set_pos.
  self.al, self.adx, self.ady = a, x, y
end
function Widget:set_text(t)
  check(type(t) == "string", "set_text needs string")
  self.text = t
end
function Widget:set_value(v) int(v, "set_value") end
function Widget:hidden(b) self.shown = not b end
function Widget:style(t, sel)
  check(type(t) == "table", "style needs a table")
  for k, v in pairs(t) do
    check(STYLE_KEYS[k], "unknown style key: " .. tostring(k))
    if k:match("color") then
      int(v, "style " .. k)
      check(v >= 0 and v <= 0xffffff, "style " .. k .. " out of range: " .. v)
    end
  end
  if sel then check(type(sel) == "string", "style selector") end
  -- Remember the style. Validating and discarding means no tool downstream
  -- can draw what the app actually looks like, which is how a design gets
  -- iterated blind.
  if not sel then
    self.st = self.st or {}
    for k, v in pairs(t) do self.st[k] = v end
  end
end

local lowheap = false   -- set from argv below; declared here so that
                        -- badge.sys.stats closes over the local
local store, now = {}, 0
local logs = {}
local leds, lit, shows = {0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0}, 0

-- Total light currently latched on the strip. 0 means dark.
local function led_total()
  local t = 0
  for i = 1, 6 do t = t + (lit[i] or 0) end
  return t
end

-- Brightest single led seen across the whole run, as r+g+b. A state can be
-- logically "on" and still look off: the firmware applies a brightness curve
-- that flattens small values, so a few percent of full is not a visible led.
local peak = 0
local function note_peak()
  for i = 1, 6 do
    if (lit[i] or 0) > peak then peak = lit[i] end
  end
end

badge = {
  ui = {
    screen_width = 320, screen_height = 240,
    label = function() return new_widget("label") end,
    -- Record the size a box is born with.  Without this, a widget that is
    -- never passed through set_size has no .w and vanishes from the preview,
    -- which is how the egg came to look like an empty screen.
    box = function(_, w, h)
      local b = new_widget("box")
      b.w, b.h = w, h
      return b
    end,
    bar = function() return new_widget("bar") end,
    line = function() return new_widget("line") end,
    arc = function() return new_widget("arc") end,
  },
  -- The strip is modelled, not just validated: "the lights will not come back
  -- on" is a state bug, and a mock that discards every value cannot see one.
  -- leds holds the staged frame; lit holds what the last show() latched.
  led = {
    count = function() return 6 end,
    clear = function() for i = 1, 6 do leds[i] = 0 end end,
    show = function()
      for i = 1, 6 do lit[i] = leds[i] end
      shows = shows + 1
      note_peak()
    end,
    set = function(i, r, g, b)
      int(i, "led index"); check(i >= 1 and i <= 6, "led index range: " .. i)
      for _, c in ipairs({{r, "r"}, {g, "g"}, {b, "b"}}) do
        int(c[1], "led " .. c[2])
        check(c[1] >= 0 and c[1] <= 255,
              "led " .. c[2] .. " out of range: " .. tostring(c[1]))
      end
      leds[i] = r + g + b
    end,
  },
  contacts = {
    count = function() return #contacts end,
    get = function(i) return contacts[i] end,
  },
  me = {
    name = function() return "Matthew Zhu" end,
    role = function() return "Hacker" end,
    role_name = function() return "Hacker" end,
    color = function() return 90, 200, 255 end,
    badge_id = function() return "moon-honey-opal-bloom" end,
    provisioned = function() return true end,
  },
  -- Note: this table IS the backing store.  Keys an app uses must not collide
  -- with the four method names below.
  store = {
    get_int = function(k, d) return store[k] or d end,
    set_int = function(k, v) int(v, "store " .. k); store[k] = v end,
    get = function(k, d) return store[k] or d end,
    set = function(k, v) store[k] = v end,
  },
  sys = {
    ms = function() return now end,
    uptime = function() return now // 1000 end,
    log = function(s) logs[#logs + 1] = s end,
    random = function(n) return n and math.random(0, n - 1) or math.random(0, 2^31) end,
    stats = function()
      return {lua_used = 30000, lua_limit = 98304, lua_peak = 31000,
              widgets = widgets, uptime_ms = now,
              free_heap = lowheap and 18000 or 40000}
    end,
    version = function() return "mock" end,
  },
  sensor = {
    accel = function() return 0, 0, 1000 end,
    shake = function() return false end,
    tap = function() return false end,
    orientation = function() return "top_edge" end,
  },
  input = {
    BUTTON = {A=1, B=2, HOME=3, DOWN=4, LEFT=5, RIGHT=6, UP=7, AUX1=8, START=9},
    KIND = {PRESSED=1, RELEASED=2},
    is_down = function() return false end,
    held = function() return 0 end,
  },
  app = {slug = function() return "mock" end, name = function() return "mock" end,
         exit = function() end},
}

local src = assert(io.open(app_path)):read("a")
local chunk = assert(load(src, "@" .. app_path))
chunk()

local root = new_widget("root")
assert(on_enter, "app defines no on_enter")

-- A badge that has already hatched.  Without this every run starts with an
-- empty store, the app arms the egg at the current contact count, and the
-- whole creature path goes untested.
local hatched = false
for i = 1, 5 do
  if arg[i] == "hatched" then hatched = true end
  -- An app that sizes itself to free_heap needs its low-memory path walked,
  -- or the degraded case only ever runs on someone else's badge.
  if arg[i] == "lowheap" then lowheap = true end
end
if hatched then store.hatch = 0 end

local ok, err = pcall(on_enter, root)
check(ok, "on_enter errored: " .. tostring(err))

local function ticks(n)
  for _ = 1, n do
    now = now + 50
    if not on_tick then return true end
    local o, e = pcall(on_tick)
    check(o, "on_tick errored at t=" .. now .. ": " .. tostring(e))
    if not o then return false end
  end
  return true
end

-- The app builds itself incrementally, so give it time to finish loading,
-- then cover the celebration window and steady state.
ticks(400)
local built = widgets
-- Only an app that builds itself across ticks can stall half-built.
if on_tick then
  check(built > 5, "app never finished loading: only " .. built .. " widgets")
end

-- Buttons, each followed by ticks so any queued work drains (A rescans).
-- LEFT and RIGHT are walked past both ends so the attribution cursor wraps
-- through every segment and back to "none" in both directions.
-- The trailing RIGHTs leave a segment picked, so a preview run shows what
-- attribution actually says rather than the default summary line.
-- B is deliberately absent here: it is a toggle, and the dedicated test below
-- needs to start from a known lights-on state.
for _, b in ipairs({1, 7, 4, 6, 6, 6, 6, 5, 5, 5, 5, 1, 9, 6, 6}) do
  if not on_button then break end
  local o, e = pcall(on_button, b, 1)
  check(o, "on_button(" .. b .. ") errored: " .. tostring(e))
  if not ticks(80) then break end
end
check(widgets == built,
      "rescan leaked widgets: " .. built .. " -> " .. widgets)

-- B is a toggle, so it has to survive being pressed twice. Nothing else here
-- presses a button more than once, which is how an off-and-stays-off bug
-- reaches a badge through a green gate.
-- Skipped for an app that does not use the strip at all: it has no B toggle
-- and no brightness to be wrong about.
if on_button and peak > 0 then
  local before = led_total()
  check(before > 0, "leds were already dark before the B toggle test")
  pcall(on_button, 2, 1); ticks(4)
  check(led_total() == 0,
        "B did not turn the leds off: total " .. led_total())
  pcall(on_button, 2, 1); ticks(4)
  check(led_total() > 0,
        "B did not turn the leds back on: they stayed dark")
end

-- At default brightness some led must actually reach a visible level at some
-- point. 200 of a possible 765 is roughly one led at a third of full. This is
-- the check that would have caught the egg lighting two leds at 10-33%.
if peak > 0 then
  check(peak >= 200,
        "no led ever got bright enough to read: peak r+g+b was " .. peak
        .. ", floor is 200. A state that is logically on but this dim looks "
        .. "off on the badge.")
end

if on_exit then
  local o, e = pcall(on_exit)
  check(o, "on_exit errored: " .. tostring(e))
end

if arg[3] == "preview" then
  -- coarse silhouette of the last drawn frame, 4px per column, 6px per row
  local cols, rows = 80, 40
  local grid = {}
  for r = 1, rows do grid[r] = {} for c = 1, cols do grid[r][c] = " " end end
  for _, w in ipairs(all) do
    if w.shown and w.x and w.w and w.n > 1 and w.w < 300 then
      local ch = "#"
      if w.w <= 8 then ch = "*" end
      if w.w >= 40 then ch = "O" end
      for c = math.floor(w.x / 4) + 1, math.floor((w.x + w.w - 1) / 4) + 1 do
        for r = math.floor(w.y / 6) + 1, math.floor((w.y + w.h - 1) / 6) + 1 do
          if grid[r] and grid[r][c] then grid[r][c] = ch end
        end
      end
    end
  end
  print("+" .. string.rep("-", cols) .. "+")
  for r = 1, rows do print("|" .. table.concat(grid[r]) .. "|") end
  print("+" .. string.rep("-", cols) .. "+")

  -- The silhouette cannot show words, and most of what this app says to the
  -- user is a label. Dump the visible ones so a preview can be read.
  print("text on screen:")
  for _, w in ipairs(all) do
    if w.shown and w.text and w.text ~= "" then
      print("   " .. w.text)
    end
  end
end

print(("app       %s"):format(app_path))
print(("contacts  %d"):format(n_contacts))
print(("widgets   %d / 512"):format(widgets))
print(("logs      %d line(s)"):format(#logs))
for _, l in ipairs(logs) do print("   " .. l) end
if #fails == 0 then
  print("RESULT    pass")
else
  print(("RESULT    %d FAILURE(S)"):format(#fails))
  local seen = {}
  for _, f in ipairs(fails) do
    if not seen[f] then seen[f] = true; print("   " .. f) end
  end
  os.exit(1)
end
