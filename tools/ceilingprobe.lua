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
-- The padding has to match the SHAPE of real code, not just its size.
--
-- The first version of this tool padded with many tiny functions, and it
-- reported a failure at 13,750 that said nothing about the apps we care
-- about. Measured:
--
--   apps/bump_pets.lua    14542 body bytes    21 prototypes    692 bytes each
--   wip/animal.lua        15576 body bytes    19 prototypes    820 bytes each
--   the old probe         13667 body bytes   137 prototypes    100 bytes each
--
-- Every Lua Proto carries fixed overhead: a constant array, upvalue
-- descriptors, a code array, a nested-proto array and debug info. At 7 to 8
-- times the prototype count, that probe was far more expensive per byte than
-- any real app, so it hit the allocator early and measured its own shape.
--
-- So: few, large functions, at the same bytes-per-prototype as the real apps.
-- Constants are varied deliberately, because identical literals get pooled
-- into a single constant-table entry and would understate the cost.
local SLUG = "ceil_probe"
local DENSITY = 750   -- body bytes per prototype, from the table above

local function header(size)
  return "--[==[badge-app\nslug=" .. SLUG .. "\nname=Ceiling " .. size
    .. "\nicon=CEIL\napi=2\nheap_kb=96\n]==]\n"
end

-- One statement inside a padding function: a few instructions and two
-- constants that differ from every other statement's.
local function stmt(n)
  return string.format(
    'v=a*%d+b//%d if v>%d then v=v-%d end t[#t+1]=v+%d\n',
    31 + n % 97, 3 + n % 13, 200 + n % 55, 100 + n % 41, n % 29)
end

-- One padding function, built to an approximate byte size. Only two locals
-- live at once, so the value-stack cost stays where real code puts it.
local function unit(n, want)
  local head = string.format('P[%d]=function(a,b)\nlocal v,t=%d,{}\n', n, n)
  local foot = 'return v,t\nend\n'
  local out, i = {head}, 0
  local used = #head + #foot
  while used < want do
    i = i + 1
    local ln = stmt(n * 1000 + i)
    out[#out + 1] = ln
    used = used + #ln
  end
  out[#out + 1] = foot
  return table.concat(out)
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

  -- Enough functions to land at the real apps' bytes-per-prototype.
  local want = size - fixed
  local count = math.max(1, math.floor(want / DENSITY))

  local body, n = {}, 0
  local used = fixed
  while n < count do
    local u = unit(n + 1, want // count)
    if used + #u > size then break end
    n = n + 1
    body[n] = u
    used = used + #u
  end
  if n == 0 then
    return nil, "target too small to pad at this density"
  end

  -- Close the remainder with single statements, then one comment to land on
  -- the target exactly. A trailing comment is the only filler that cannot
  -- change the instruction stream, and it is the last few bytes only.
  local i = 0
  while true do
    i = i + 1
    local ln = stmt(900000 + i)
    if used + #ln + #foot > size then break end
    -- Append inside the last function, before its return.
    body[n] = body[n]:gsub("return v,t\n", ln .. "return v,t\n", 1)
    used = used + #ln
  end

  local gap = size - used
  if gap > 0 then
    if gap < 3 then
      return nil, string.format("cannot land on %d exactly (%d bytes short of "
        .. "a clean fill); try a size 3 or more away", size, gap)
    end
    body[n + 1] = "--" .. string.rep("x", gap - 3) .. "\n"
    used = size
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
