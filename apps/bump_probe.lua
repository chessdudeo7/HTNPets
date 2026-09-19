--[==[badge-app
slug=bump_probe
name=Bump Pets Probe
icon=BP?
api=2
heap_kb=48
]==]

-- Read-only probe for the Bump Pets design.
-- Answers: does badge.contacts see the Connect book, are received_unix
-- stamps real, and what does badge.me actually hand us?
--
-- A      rescan
-- Up/Dn  walk the contact list
-- HOME   exit

local MAX_SCAN = 256

local total = 0
local role_names, role_hits, role_kinds = {}, {}, 0
local first_unix, last_unix = nil, nil
local bad_stamps = 0
local cursor = 1

local body, detail

local function fmt(v)
  if v == nil then return "nil" end
  return tostring(v)
end

local function scan()
  total, role_names, role_hits, role_kinds = 0, {}, {}, 0
  first_unix, last_unix, bad_stamps = nil, nil, 0
  local i = 1
  while i <= MAX_SCAN do
    local c = badge.contacts.get(i)
    if not c then break end
    total = i
    local key = fmt(c.role)
    if role_hits[key] == nil then
      role_kinds = role_kinds + 1
      role_names[role_kinds] = key
      role_hits[key] = 0
    end
    role_hits[key] = role_hits[key] + 1
    local t = c.received_unix
    if type(t) == "number" and t > 1000000000 then
      if first_unix == nil or t < first_unix then first_unix = t end
      if last_unix == nil or t > last_unix then last_unix = t end
    else
      bad_stamps = bad_stamps + 1
    end
    i = i + 1
  end
end

local function summary()
  local span = "span n/a"
  if first_unix and last_unix then
    span = "span " .. math.floor((last_unix - first_unix) / 60) .. " min"
  end
  local rl = ""
  for i = 1, role_kinds do
    local k = role_names[i]
    rl = rl .. k .. ":" .. role_hits[k] .. "  "
  end
  if rl == "" then rl = "no roles seen" end
  return "count() " .. fmt(badge.contacts.count()) .. "   walked " .. total ..
         "\n" .. span .. "   bad stamps " .. bad_stamps ..
         "\n" .. rl
end

local function show_detail()
  if total == 0 then
    detail:set_text("No contacts yet.\nBump two badges with Connect, then A.")
    return
  end
  if cursor < 1 then cursor = total end
  if cursor > total then cursor = 1 end
  local c = badge.contacts.get(cursor)
  if not c then
    detail:set_text("get(" .. cursor .. ") returned nil")
    return
  end
  detail:set_text(cursor .. "/" .. total .. "  " .. fmt(c.name) ..
    "\nrole " .. fmt(c.role) .. "   id " .. fmt(c.badge_id) ..
    "\nreceived_unix " .. fmt(c.received_unix))
end

function on_enter(root)
  local head = badge.ui.label(root, "Bump Pets Probe")
  head:align("top_mid", 0, 6)

  local me = badge.ui.label(root, "")
  me:style({text_font = 14, text_align = "center"})
  me:align("top_mid", 0, 30)

  local prov = badge.me.provisioned()
  local ctext = "color n/a"
  if prov then
    local r, g, b = badge.me.color()
    ctext = "color " .. fmt(r) .. "," .. fmt(g) .. "," .. fmt(b)
  end
  me:set_text("me: " .. fmt(badge.me.name()) .. " / " .. fmt(badge.me.role_name()) ..
    "\nid " .. fmt(badge.me.badge_id()) .. "   provisioned " .. fmt(prov) ..
    "\n" .. ctext)

  body = badge.ui.label(root, "")
  body:style({text_font = 14, text_align = "center"})
  body:align("top_mid", 0, 92)

  detail = badge.ui.label(root, "")
  detail:style({text_font = 14, text_align = "center"})
  detail:align("top_mid", 0, 150)

  local hint = badge.ui.label(root, "A rescan   Up/Down walk list   HOME exit")
  hint:style({text_font = 14})
  hint:align("bottom_mid", 0, -8)

  scan()
  body:set_text(summary())
  show_detail()

  badge.sys.log("fw=" .. fmt(badge.sys.version()))
  badge.sys.log("uptime_s=" .. fmt(badge.sys.uptime()) .. " ms=" .. fmt(badge.sys.ms()))
  badge.sys.log("contacts count=" .. fmt(badge.contacts.count()) .. " walked=" .. total)
  badge.sys.log("first_unix=" .. fmt(first_unix) .. " last_unix=" .. fmt(last_unix))
  badge.sys.log("legacy config_get type=" .. type(badge.config_get))
  local s = badge.sys.stats()
  badge.sys.log("lua=" .. fmt(s.lua_used) .. "/" .. fmt(s.lua_limit) ..
    " widgets=" .. fmt(s.widgets) .. " free_heap=" .. fmt(s.free_heap))
end

function on_button(button, kind)
  if kind ~= badge.input.KIND.PRESSED then return end
  local B = badge.input.BUTTON
  if button == B.A then
    scan()
    body:set_text(summary())
    show_detail()
  elseif button == B.UP then
    cursor = cursor - 1
    show_detail()
  elseif button == B.DOWN then
    cursor = cursor + 1
    show_detail()
  end
end
