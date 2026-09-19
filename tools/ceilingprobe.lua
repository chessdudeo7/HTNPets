-- Generate a badge app padded to an exact size, to find the real
-- compile-memory ceiling.
--
--   lua tools/ceilingprobe.lua 13750
--   lua tools/ceilingprobe.lua 13000 13750 14500
--
-- Writes dist/ceil_<size>.lua for each size. Push one, open it, and read what
-- the screen says. A probe that opens prints its own size and the heap stats;
-- one that is over the ceiling dies in main.lua before on_enter runs, with
-- "Lua memory limit exceeded".
--
-- What is known so far, measured on hardware:
--   11575  loads
--   12524  loads   (wip/animal.lua)
--   15670  fails   "Lua memory limit exceeded" in main.lua
-- The real ceiling is somewhere in that band. check.lua's 13000 is a
-- conservative guess, not a measurement.
--
-- The padding is representative on purpose. A giant comment would be stripped
-- and a giant string literal would be one constant; neither loads the parser
-- the way real code does. Each padding unit is a small function with its own
-- prototype, constants and instructions, which is what actually costs memory.
-- They live in one table because a file-level local costs a main-chunk slot
-- and the slot ceiling is 25.

local SLUG = "ceil_probe"

local function header(size)
  return "--[==[badge-app\nslug=" .. SLUG .. "\nname=Ceiling " .. size
    .. "\nicon=CEIL\napi=2\nheap_kb=96\n]==]\n"
end

-- One padding unit, about 90 bytes, carrying a prototype, three constants and
-- a dozen instructions.
local function unit(n)
  return string.format(
    'P[%d]=function(a,b) local s="pad%04dxy" local t=a*%d+b%%%d '
    .. 'if t>%d then t=t-%d end return s,t end\n',
    n, n, 31 + n % 61, 7 + n % 23, 90 + n % 9, 90 + n % 9)
end

local function tail(size)
  return table.concat({
    "function on_enter(root)\n",
    'local l=badge.ui.label(root,"CEILING PROBE\\n', size,
    ' bytes\\nLOADED OK")\n',
    'l:style({text_font=20,text_align="center"})\n',
    'l:align("center",0,-30)\n',
    "local s=badge.sys.stats()\n",
    'local m=badge.ui.label(root,"lua "..s.lua_used.."/"..s.lua_limit',
    '.."  peak "..s.lua_peak.."\\nfree heap "..s.free_heap.."  units "..#P)\n',
    'm:style({text_font=14,text_align="center"})\n',
    'm:align("center",0,40)\n',
    'badge.sys.log("ceiling ', size, ' LOADED lua_used="..s.lua_used',
    '.." peak="..s.lua_peak.." limit="..s.lua_limit',
    '.." free_heap="..s.free_heap.." units="..#P)\n',
    "end\n",
  })
end

local function build(size)
  local head = header(size) .. "local P={}\n"
  local foot = tail(size)
  local fixed = #head + #foot

  if fixed > size then
    return nil, string.format("%d is below the %d-byte floor of the probe "
      .. "itself", size, fixed)
  end

  -- Add whole units until one more would overshoot.
  local body, n = {}, 0
  local used = fixed
  while true do
    local u = unit(n + 1)
    if used + #u > size then break end
    n = n + 1
    body[n] = u
    used = used + #u
  end

  -- Close the remaining gap by stretching one unit's string literal, so the
  -- file lands on the target exactly rather than near it.
  local gap = size - used
  if gap > 0 then
    if n == 0 then
      return nil, "target too small to pad exactly"
    end
    local u = body[n]
    body[n] = u:gsub('"pad(%d+)xy"', '"pad%1' .. string.rep("z", gap) .. 'xy"', 1)
    used = used + gap
  end

  return head .. table.concat(body) .. foot, nil, n
end

local targets = {}
for i = 1, #arg do
  local v = tonumber(arg[i])
  if not v then
    io.stderr:write("not a size: " .. arg[i] .. "\n")
    os.exit(1)
  end
  targets[#targets + 1] = math.floor(v)
end
if #targets == 0 then targets = {13000, 13750, 14500} end

os.execute(package.config:sub(1, 1) == "\\" and "mkdir dist 2>nul"
                                             or "mkdir -p dist 2>/dev/null")

print("Generated probes. Push one at a time and record what the badge does.")
print("")
for _, size in ipairs(targets) do
  local src, err, units = build(size)
  if not src then
    print(string.format("  %5d  SKIPPED: %s", size, err))
  else
    local path = "dist/ceil_" .. size .. ".lua"
    local f = assert(io.open(path, "wb"))
    f:write(src)
    f:close()
    local body = src:match("%]==%]\n(.*)$")
    print(string.format("  %5d  %-26s  %3d units, %d bytes reach the compiler",
      #src, path, units, #body))
    if #src ~= size then
      print(string.format("         WARNING wanted %d, wrote %d", size, #src))
    end
  end
end
print("")
print("All share the slug " .. SLUG .. ", so they overwrite each other and")
print("never touch htn_bump_pets. Reboot between pushes: a failed Lua state")
print("can leave memory retained, which would bias the next result.")
