-- Draw what the app actually looks like, as an SVG at real badge size.
--
--   lua tools/render.lua apps/bump_pets.lua 12 hatched out.svg
--
-- The ASCII silhouette in mockbadge answers "is something on screen". It
-- cannot answer "is this cute", which is the question that decides whether
-- this app wins a prize judged partly on user experience. Designing a
-- character against a grid of hash marks is designing blind.
--
-- This is an approximation, not an emulator: LVGL's exact text metrics,
-- anti-aliasing and shadow rendering are not reproduced. It is close enough
-- to judge proportion, colour, balance and silhouette, which is most of what
-- separates a cute creature from a pile of circles.

local app_path = arg[1] or "apps/bump_pets.lua"
local contacts = arg[2] or "12"
local flags = {}
local out_path = "dist/preview.svg"
for i = 3, #arg do
  if arg[i]:match("%.svg$") then out_path = arg[i] else flags[#flags + 1] = arg[i] end
end

-- Run the app under the mock, then read the widget tree back out of it.
-- mockbadge is a script, not a module, so it is loaded with the globals it
-- expects and asked to hand over `all` at the end.
local dump = os.tmpname() .. ".lua"
local f = assert(io.open("test/mockbadge.lua"))
local src = f:read("a")
f:close()

-- Append an exporter to a copy of the harness.
local exporter = [[

do
  local out = assert(io.open(os.getenv("RENDER_DUMP"), "wb"))
  out:write("return {\n")
  for _, w in ipairs(all) do
    local st = w.st or {}
    out:write(string.format(
      "{kind=%q,shown=%s,x=%s,y=%s,w=%s,h=%s,text=%q,al=%q,adx=%s,ady=%s,"
      .. "bg=%s,radius=%s,bc=%s,bw=%s,tc=%s,tf=%s,op=%s},\n",
      w.kind, tostring(w.shown), tostring(w.x), tostring(w.y),
      tostring(w.w), tostring(w.h), tostring(w.text or ""),
      tostring(w.al or ""), tostring(w.adx or 0), tostring(w.ady or 0),
      tostring(st.bg_color), tostring(st.radius), tostring(st.border_color),
      tostring(st.border_width), tostring(st.text_color),
      tostring(st.text_font), tostring(st.bg_opa)))
  end
  out:write("}\n")
  out:close()
end
]]

local tmp_harness = os.tmpname() .. ".lua"
local h = assert(io.open(tmp_harness, "wb"))
h:write(src .. exporter)
h:close()

local LUA = arg[-1] or "lua"
local cmd = string.format('set "RENDER_DUMP=%s" && %s %s %s %s', dump, LUA,
  tmp_harness, app_path, contacts)
if package.config:sub(1, 1) ~= "\\" then
  cmd = string.format('RENDER_DUMP=%s %s %s %s %s', dump, LUA, tmp_harness,
    app_path, contacts)
end
for _, fl in ipairs(flags) do cmd = cmd .. " " .. fl end
os.execute(cmd)
os.remove(tmp_harness)

local chunk = loadfile(dump)
if not chunk then
  io.stderr:write("the app did not run; check `lua check.lua` first\n")
  os.exit(1)
end
local ws = chunk()
os.remove(dump)

-- Where a widget sits. Boxes get set_pos; labels only ever get align(), so
-- their position is derived from the alignment against the 320x240 screen.
local function place(w)
  if w.x and w.y then return w.x, w.y end
  local tw = math.max(#(w.text or "") * ((w.tf or 16) * 0.55), 8)
  local th = (w.tf or 16) + 2
  local a, dx, dy = w.al or "center", w.adx or 0, w.ady or 0
  local x, y = 160 - tw / 2, 120 - th / 2
  if a:find("top") then y = dy end
  if a:find("bottom") then y = 240 - th + dy end
  if a == "center" then y = 120 - th / 2 + dy end
  if a:find("left") then x = dx end
  if a:find("right") then x = 320 - tw + dx end
  if a:find("mid") or a == "center" then x = 160 - tw / 2 + dx end
  return x, y, tw, th
end

local function hex(v)
  if not v then return nil end
  return string.format("#%06x", v)
end

local parts = {
  string.format('<svg xmlns="http://www.w3.org/2000/svg" width="640" '
    .. 'height="480" viewBox="0 0 320 240" shape-rendering="geometricPrecision">'),
  '<rect width="320" height="240" fill="#000"/>',
}

for _, w in ipairs(ws) do
  if w.shown then
    if w.kind == "label" then
      local x, y, tw, th = place(w)
      local size = w.tf or 16
      local fill = hex(w.tc) or "#e8eef5"
      local anchor, tx = "start", x
      if (w.al or ""):find("mid") or w.al == "center" then
        anchor, tx = "middle", x + tw / 2
      elseif (w.al or ""):find("right") then
        anchor, tx = "end", x + tw
      end
      local line_n = 0
      for line in (w.text or ""):gmatch("[^\n]+") do
        parts[#parts + 1] = string.format(
          '<text x="%.1f" y="%.1f" font-family="DejaVu Sans,Verdana,sans-serif"'
          .. ' font-size="%d" fill="%s" text-anchor="%s">%s</text>',
          tx, y + size + line_n * (size + 2), size, fill, anchor,
          (line:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")))
        line_n = line_n + 1
      end
    elseif w.x and w.w then
      local fill = hex(w.bg) or "none"
      if w.op == 0 then fill = "none" end
      local r = w.radius or 0
      if r > math.min(w.w, w.h) / 2 then r = math.min(w.w, w.h) / 2 end
      local stroke = ""
      if w.bw and w.bw > 0 and w.bc then
        stroke = string.format(' stroke="%s" stroke-width="%d"', hex(w.bc), w.bw)
      end
      parts[#parts + 1] = string.format(
        '<rect x="%d" y="%d" width="%d" height="%d" rx="%.1f" fill="%s"%s/>',
        w.x, w.y, w.w, w.h, r, fill, stroke)
    end
  end
end

parts[#parts + 1] = "</svg>"

os.execute(package.config:sub(1, 1) == "\\" and "mkdir dist 2>nul"
                                             or "mkdir -p dist 2>/dev/null")
local o = assert(io.open(out_path, "wb"))
o:write(table.concat(parts, "\n"))
o:close()
print(string.format("%s  (%d widgets, %d drawn)", out_path, #ws, #parts - 3))
