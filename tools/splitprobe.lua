-- Generate a MULTI-FILE badge app, to find out whether require() lowers the
-- peak contiguous allocation that the compiler needs.
--
--   lua tools/splitprobe.lua 14000 3
--
-- Writes dist/split/main.lua (single-file format, importable) and
-- dist/split/mod1.lua .. modN.lua (added in the IDE with the + button).
--
-- Why this exists. apps/bump_pets.lua at 13,793 bytes fails with
-- "Lua memory limit exceeded (used 43524, peak 47027)" on a heap reporting
-- free=70220 largest=57344, while a 15,670-byte single-file probe loads
-- happily at used 51596. So the wall is not total bytes and not the quota:
-- it is one large contiguous block the parser needs while compiling a chunk.
-- The same app loads when largest is 63,488 and fails when it is 57,344.
--
-- The whole chunk is parsed before anything runs, so a monolith needs its
-- peak in one piece. If the chunk is split, the parser only ever holds one
-- module at a time and the peak block should fall to roughly the largest
-- module. Total live memory afterwards is about the same; it is the PEAK
-- that this is meant to move.
--
-- The badge supports require() (16 modules, depth 8) and Share carries the
-- modules with the app, so a split app still spreads badge to badge. Only
-- the IDE's single-file import is limited to two files.

local DENSITY = 750   -- body bytes per prototype, matching the real apps
local OUT = "dist/split"

local function stmt(n)
  return string.format(
    'v=a*%d+b//%d if v>%d then v=v-%d end t[#t+1]=v+%d\n',
    31 + n % 97, 3 + n % 13, 200 + n % 55, 100 + n % 41, n % 29)
end

-- One function inside a module, built to an approximate byte size.
local function unit(mod, n, want)
  local head = string.format('M[%d]=function(a,b)\nlocal v,t=%d,{}\n', n, n)
  local foot = 'return v,t\nend\n'
  local out = {head}
  local used = #head + #foot
  while used < want do
    local ln = stmt(mod * 100000 + n * 1000 + #out)
    out[#out + 1] = ln
    used = used + #ln
  end
  out[#out + 1] = foot
  return table.concat(out)
end

-- A module: a table of padding functions, returned to the requirer.
local function module(mod, want)
  local head = "local M={}\n"
  local foot = "return M\n"
  local body, n = {}, 0
  local used = #head + #foot
  local count = math.max(1, (want - used) // DENSITY)
  while n < count do
    local u = unit(mod, n + 1, (want - used) // count)
    if used + #u > want then break end
    n = n + 1
    body[n] = u
    used = used + #u
  end
  -- Land on the target with a trailing comment; it cannot change any opcode.
  local gap = want - used
  if gap >= 3 then
    body[#body + 1] = "--" .. string.rep("x", gap - 3) .. "\n"
    used = want
  end
  return head .. table.concat(body) .. foot, n, used
end

local total = tonumber(arg[1]) or 14000
local mods = tonumber(arg[2]) or 3

local header = table.concat({
  "--[==[badge-app\n",
  "slug=split", total, "\n",
  "name=Split ", total, " x", mods, "\n",
  "icon=SPLT\napi=2\nheap_kb=96\n]==]\n",
})

-- main.lua requires every module, then reports. Kept deliberately small:
-- the point is that no single chunk is large.
local req = {}
for i = 1, mods do
  req[#req + 1] = string.format('R[%d]=require("mod%d")\n', i, i)
end
local main_body = table.concat({
  "local R={}\n",
  table.concat(req),
  "function on_enter(root)\n",
  'local n=0\nfor i=1,#R do for _ in pairs(R[i]) do n=n+1 end end\n',
  'local l=badge.ui.label(root,"SPLIT PROBE\\n', total, ' bytes / ', mods,
  ' modules\\nLOADED OK")\n',
  'l:style({text_font=20,text_align="center"})\nl:align("center",0,-30)\n',
  "local s=badge.sys.stats()\n",
  'local m=badge.ui.label(root,"lua "..s.lua_used.."/"..s.lua_limit',
  '.."  peak "..s.lua_peak.."\\nfree heap "..s.free_heap.."  fns "..n)\n',
  'm:style({text_font=14,text_align="center"})\nm:align("center",0,40)\n',
  'badge.sys.log("split ', total, ' x', mods, ' LOADED lua_used="..s.lua_used',
  '.." peak="..s.lua_peak.." free_heap="..s.free_heap.." fns="..n)\n',
  "end\n",
})

local main = header .. main_body
local per = (total - #main) // mods

if per < 200 then
  io.stderr:write("too small to split that many ways\n")
  os.exit(1)
end

os.execute(package.config:sub(1, 1) == "\\"
  and "mkdir dist\\split 2>nul" or "mkdir -p dist/split 2>/dev/null")

local f = assert(io.open(OUT .. "/main.lua", "wb"))
f:write(main)
f:close()

print("Split probe. main.lua goes through Import app; the modules are added")
print("in the IDE with the + button, one file each, named exactly as below.")
print("")
print(string.format("  %-22s %6d bytes   (manifest + requires + on_enter)",
  OUT .. "/main.lua", #main))

local sum = #main
for i = 1, mods do
  local src, fns, used = module(i, per)
  local p = OUT .. "/mod" .. i .. ".lua"
  local h = assert(io.open(p, "wb"))
  h:write(src)
  h:close()
  sum = sum + used
  print(string.format("  %-22s %6d bytes   %d functions", p, used, fns))
end

print("")
print(string.format("  total across files     %6d bytes", sum))
print(string.format("  largest single chunk   %6d bytes   <- the number that",
  math.max(#main, per)))
print("                                        should decide whether it loads")
print("")
print("Compare against a single-file probe of the same total. If the split")
print("one loads where the monolith does not, the wall is the per-chunk peak")
print("and splitting apps/bump_pets.lua is the fix.")
