-- Everything checkable without a badge. Works in PowerShell, cmd and bash.
--   lua check.lua
-- Add new apps to the APPS list below.

local APPS = {"apps/bump_pets.lua", "apps/bump_probe.lua"}
local MOCK_APP = "apps/bump_pets.lua"
local MOCK_COUNTS = {0, 1, 5, 12, 40, 200}
local SLOT_CEILING = 25   -- above this the badge raises "stack safety limit"
-- Compile-time memory ceiling, measured on hardware:
--   11575 bytes  compiles and runs
--   15670 bytes  "Lua memory limit exceeded" in main.lua, before on_enter
-- The whole chunk is parsed and compiled before any callback, and that peak
-- is what blows. Stay well under.
local SRC_CEILING = 13000

local LUA = arg[-1] or "lua"
local LUAC = LUA:gsub("lua(%.exe)$", "luac%1"):gsub("([^c])lua$", "%1luac")

local function q(s)
  if s:find("[ \\]") then return '"' .. s .. '"' end
  return s
end

local function sh(cmd)
  local p = io.popen(cmd .. " 2>&1")
  if not p then return nil, "popen failed" end
  local out = p:read("a")
  local ok = p:close()
  return out, ok
end

local status = 0
local function fail(msg)
  status = 1
  print("    FAIL " .. msg)
end

-- identifiers the badge Lua sandbox does not provide
local BANNED = {
  "pcall", "xpcall", "loadfile", "dofile", "setmetatable", "getmetatable",
  "os%.", "io%.", "coroutine%.", "package%.", "debug%.",
}

print("### build")
do
  local out, ok = sh(q(LUA) .. " build.lua")
  for l in (out or ""):gmatch("[^\n]+") do
    if not l:match("^###") then print("  " .. l:gsub("^%s+", "")) end
  end
  if not ok then
    fail("build.lua failed; dist/ is not trustworthy")
  end
end

print("")
print("### lint")
for _, path in ipairs(APPS) do
  local f = io.open(path)
  if not f then
    fail(path .. " not found")
  else
    local src = f:read("a")
    f:close()
    print("  " .. path .. "  " .. #src .. " bytes")

    if not src:match("^%-%-%[==%[badge%-app\n") then
      fail("missing badge-app header on line 1")
    end
    if not src:match("\n%]==%]\n") then
      fail("missing closing ]==] delimiter")
    end
    for _, k in ipairs({"slug", "name", "api"}) do
      if not src:match("\n" .. k .. "=") then
        fail("manifest missing " .. k .. "=")
      end
    end
    for _, b in ipairs(BANNED) do
      local line = 0
      for l in src:gmatch("[^\n]*") do
        line = line + 1
        if not l:match("^%s*%-%-") and l:find(b) then
          fail("uses " .. b:gsub("%%", "") .. " (absent from sandbox) at line " .. line)
          break
        end
      end
    end
    if src:find("badge%.label%s*%(") or src:find("badge%.box%s*%(") then
      fail("uses api=1 only factories; use badge.ui.*")
    end
    local bad = src:find("[\128-\255]")
    if bad then
      local upto = src:sub(1, bad)
      local _, n = upto:gsub("\n", "")
      fail("non-ASCII byte at line " .. (n + 1) .. " (fonts render these as squares)")
    end
    -- The ceiling applies to what actually gets pasted into the IDE, which is
    -- the minified copy in dist/, not this readable source.  build.lua proves
    -- the two compile to the same instruction stream.
    local df = io.open("dist/" .. path:match("([^/]+)$"))
    if not df then
      fail("no dist/ output; run `lua build.lua` first")
    else
      local dist = df:read("a")
      df:close()
      print(string.format("    dist %d bytes  (headroom %d)", #dist,
                          SRC_CEILING - #dist))
      if #dist > 49152 then
        fail("over the 48 KiB Share bundle cap; cannot be shared badge to badge")
      end
      if #dist > SRC_CEILING then
        fail(string.format(
          "dist is %d bytes, over the %d byte compile-memory ceiling; the badge "
          .. "will raise \"Lua memory limit exceeded\" in main.lua before "
          .. "on_enter runs", #dist, SRC_CEILING))
      end
    end

    local out, ok = sh(q(LUAC) .. " -p " .. q(path))
    if ok then
      print("    syntax ok")
    else
      fail("lua syntax:\n" .. out)
    end
  end
end

print("")
print("### value-stack slots (the probe that never fails: main 16, max fn 17)")
for _, path in ipairs(APPS) do
  local out = sh(q(LUAC) .. " -l " .. q(path))
  if not out or out == "" then
    print("  " .. path .. "  skipped (luac unavailable)")
  else
    local mainslots, maxslots = 0, 0
    local after_main = false
    for chunkline, slots in out:gmatch("(\n[mf][^\n]*<[^\n]*)\n%s*%d+%+?%s*param[s]?, (%d+) slots") do
      slots = tonumber(slots)
      if chunkline:find("^\nmain") then mainslots = slots end
      if slots > maxslots then maxslots = slots end
      after_main = true
    end
    local note = "ok"
    if mainslots > SLOT_CEILING or maxslots > SLOT_CEILING then
      note = "TOO HIGH - expect a stack safety error"
      status = 1
    end
    print(string.format("  %-26s main=%-3d max function=%-3d  %s",
                        path, mainslots, maxslots, note))
    if not after_main then print("    (could not parse luac output)") end
  end
end

print("")
print("### headless run (mock badge API)")
for _, n in ipairs(MOCK_COUNTS) do
  local out = sh(q(LUA) .. " test/mockbadge.lua " .. q(MOCK_APP) .. " " .. n)
  if out and out:find("RESULT    pass") then
    print(string.format("  %3d contacts  pass", n))
  else
    print(string.format("  %3d contacts  FAIL", n))
    for l in (out or ""):gmatch("[^\n]+") do print("      " .. l) end
    status = 1
  end
end

print("")
if status == 0 then
  print("ALL CHECKS PASSED - safe to push to the badge")
else
  print("CHECKS FAILED - fix before pushing")
end
os.exit(status)
