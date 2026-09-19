-- Emit a byte-reduced copy of each app into dist/, for pasting into the IDE.
--   lua build.lua
--
-- Why this exists: the badge compiles the whole chunk before any callback
-- runs, and that compile peak is what raises "Lua memory limit exceeded" in
-- main.lua.  Source bytes cost roughly 2x their size in Lua memory, so
-- comments and indentation that cost a reader nothing cost the badge real
-- RAM.  The tracked source stays readable; dist/ is what gets pasted.
--
-- Safety: the minifier never reflows code and never touches a line that is
-- not entirely a comment.  Every output is then proved equivalent by
-- disassembling both with `luac -l` and comparing the instruction streams
-- with line markers and heap addresses normalised out.  A mismatch fails the
-- build rather than shipping a guess.

local APPS = {"apps/bump_pets.lua", "apps/bump_probe.lua"}

-- Test variants: the real app with a small, documented source patch, built
-- under its own slug so it can sit beside the real one on a badge.
--
-- A variant is generated, never hand-maintained. Keeping a second copy of the
-- app in the repo would mean every fix had to be made twice, and the copy
-- nobody remembers to update is the one someone tests against.
local VARIANTS = {
  {
    from = "apps/bump_pets.lua",
    out = "bump_pets_nohatch.lua",
    slug = "bump_nohatch",
    name = "Bump Pets (no egg)",
    why = "always hatched, for testing the animal without a fresh bump",
    patches = {
      {
        -- Skip arming the egg. S.hatch stays -1 and is never consulted, so
        -- the creature is drawn from whatever contacts already exist.
        from = "      if S.hatch < 0 then\n"
            .. "        S.hatch = S.total\n"
            .. "        S.dirty = true\n"
            .. "      end\n"
            .. "      S.egg = S.total <= S.hatch\n",
        to = "      S.egg = false\n",
      },
    },
  },
}
local OUT = "dist"

local LUA = arg[-1] or "lua"
local LUAC = LUA:gsub("lua(%.exe)$", "luac%1"):gsub("([^c])lua$", "%1luac")

local function q(s)
  if s:find("[ \\]") then return '"' .. s .. '"' end
  return s
end

local function sh(cmd)
  local p = io.popen(cmd .. " 2>&1")
  if not p then return nil end
  local out = p:read("a")
  p:close()
  return out
end

local function read(path, mode)
  local f = io.open(path, mode or "r")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local status = 0
local function fail(msg)
  status = 1
  print("    FAIL " .. msg)
end

-- Minify one app body.  The manifest header is returned untouched: the
-- importer parses it into manifest.cfg, and it never reaches the compiler.
local function minify(src, path)
  local header, body = src:match("^(%-%-%[==%[badge%-app\n.-\n%]==%]\n)(.*)$")
  if not header then
    return nil, "no badge-app manifest header"
  end

  -- A long comment in the body would need real lexing to strip safely.
  -- Refuse rather than corrupt the file.
  if body:find("%-%-%[=*%[") then
    return nil, "body contains a long comment (--[[ or --[==[); "
      .. "this minifier only removes whole-line short comments"
  end

  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local t = line:gsub("%s+$", "")
    -- Drop lines that are entirely a comment.  A trailing comment after code
    -- is left alone: "--" can appear inside a string literal, and telling the
    -- two apart needs a lexer.
    if t:match("^%s*%-%-") then
      t = ""
    else
      t = t:gsub("^%s+", "")
    end
    if t ~= "" then
      out[#out + 1] = t
    end
  end

  return header .. table.concat(out, "\n") .. "\n"
end

-- Disassemble both and compare the instruction stream.
--
-- Raw `luac -s` output is NOT comparable: `linedefined` and `lastlinedefined`
-- are dumped even when debug info is stripped, and they are varints, so a
-- prototype that moves from line 353 to line 300 changes the file length.
-- What must not change is the opcodes, their operands and the constants.
-- Normalise away the per-instruction [line] markers, the source:line span in
-- each prototype header, and the heap address, then compare the rest.
local function disasm(path)
  local out = sh(q(LUAC) .. " -l " .. q(path))
  if not out or out == "" then return nil end
  out = out:gsub("<[^>\n]*:%d+,%d+>", "<>")   -- source:linedefined,lastlinedefined
  out = out:gsub("%[%d+%]", "[]")             -- per-instruction line markers
  out = out:gsub("%x%x%x%x%x%x%x%x%x%x+", "ADDR") -- heap addresses (prototype headers and CLOSURE comments)
  return out
end

local function equivalent(a_path, b_path)
  local a, b = disasm(a_path), disasm(b_path)
  if not a or not b then
    return false, "could not disassemble (is luac on PATH?)"
  end
  if a ~= b then
    -- Report the first differing line, so a failure is actionable.
    local la, lb = {}, {}
    for l in a:gmatch("[^\n]*") do la[#la + 1] = l end
    for l in b:gmatch("[^\n]*") do lb[#lb + 1] = l end
    for i = 1, math.max(#la, #lb) do
      if la[i] ~= lb[i] then
        return false, string.format(
          "disassembly differs at line %d:\n      source: %s\n      dist:   %s",
          i, tostring(la[i]), tostring(lb[i]))
      end
    end
    return false, "disassembly differs"
  end
  return true
end

os.execute("mkdir " .. (package.config:sub(1, 1) == "\\" and OUT or "-p " .. OUT)
  .. " 2>" .. (package.config:sub(1, 1) == "\\" and "nul" or "/dev/null"))

print("### build")
for _, path in ipairs(APPS) do
  local src = read(path)
  if not src then
    fail(path .. " not found")
  else
    local out_path = OUT .. "/" .. path:match("([^/]+)$")
    local min, err = minify(src, path)
    if not min then
      fail(path .. ": " .. err)
    else
      write(out_path, min)
      local ok, why = equivalent(path, out_path)
      if not ok then
        fail(path .. ": " .. why)
      else
        local saved = #src - #min
        print(string.format("  %-24s %6d -> %6d bytes  (-%d, %.0f%%)  disassembly identical",
          path, #src, #min, saved, saved / #src * 100))
      end
    end
  end
end

-- Variants are built from the patched source and proved against it, not
-- against the original: the patch is a deliberate behaviour change, so only
-- the minification has to be shown to preserve meaning.
if #VARIANTS > 0 then
  print("")
  print("### variants")
end
for _, v in ipairs(VARIANTS) do
  local src = read(v.from)
  if not src then
    fail(v.from .. " not found")
  else
    local patched, ok = src, true
    for i, p in ipairs(v.patches) do
      if not patched:find(p.from, 1, true) then
        fail(v.out .. ": patch " .. i .. " no longer matches " .. v.from
          .. "; the variant needs updating with the app")
        ok = false
        break
      end
      patched = patched:gsub(p.from:gsub("%W", "%%%0"), (p.to:gsub("%%", "%%%%")), 1)
    end

    if ok then
      patched = patched:gsub("\nslug=[^\n]*", "\nslug=" .. v.slug, 1)
      patched = patched:gsub("\nname=[^\n]*", "\nname=" .. v.name, 1)

      local tmp = OUT .. "/.variant_src.lua"
      write(tmp, patched)
      local min, err = minify(patched)
      if not min then
        fail(v.out .. ": " .. err)
      else
        local out_path = OUT .. "/" .. v.out
        write(out_path, min)
        local eq, why = equivalent(tmp, out_path)
        if not eq then
          fail(v.out .. ": " .. why)
        else
          print(string.format("  %-26s %6d bytes  slug=%-14s %s",
            v.out, #min, v.slug, v.why))
        end
      end
      os.remove(tmp)
    end
  end
end

if status ~= 0 then
  print("")
  print("BUILD FAILED")
end
os.exit(status)
