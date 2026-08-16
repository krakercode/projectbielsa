-- Find the structure that holds the selected XI.
--
-- WHAT RULED OUT THE OBVIOUS ANSWER
-- A before/after differential settled it: with a tactic set up, swapping Neil
-- Taylor out for Matthew Targett at DL changed **zero bytes** across all 23 player
-- records (2 KB dumped from each, via scripts/win/dump_many.ps1). Team selection
-- is therefore NOT a field on the player. It has to be a separate structure
-- holding player POINTERS -- which is the same shape the squad itself uses
-- (std::vector<Player*>).
--
-- So: scan for pointers to one starter, then around each hit check how many of
-- the other starters land on a grid. An XI array should score 11/11.
--
-- NOTE ON A PAST MISTAKE: do NOT put an AOBScan inside the per-result loop.
-- Doing that in find_row_array.lua blocked CE's single-threaded Lua engine for
-- ~25 minutes with no way to interrupt it. Referrer lookups are a separate,
-- deliberate step here.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\find_lineup.lua]])
--   find_lineup()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\lineup.json]]
local LOG  = REPO .. [[\data\snapshots\lineup.log]]

local logf = nil
local realprint = print
local function say(...)
  realprint(...)
  if logf then
    local p = {}
    for i = 1, select("#", ...) do p[#p+1] = tostring((select(i, ...))) end
    logf:write(table.concat(p, "\t") .. "\n")
    logf:flush()
  end
end

-- Live 2026-08-16, squad vector header CEAA0240 -> begin DCA49780.
-- Starting XI as set by Quick Pick, after swapping Taylor out for Targett.
STARTERS = {
  { name = "E. Martinez",  addr = 0xD0D042A0, slot = "GK"  },
  { name = "Matty Cash",   addr = 0xD1438560, slot = "DR"  },
  { name = "Ezri Konsa",   addr = 0xD1430D40, slot = "DCR" },
  { name = "Tyrone Mings", addr = 0xD128CD40, slot = "DCL" },
  { name = "M. Targett",   addr = 0xD0F909D0, slot = "DL"  },
  { name = "M. Nakamba",   addr = 0xD0B17920, slot = "DM"  },
  { name = "Ross Barkley", addr = 0xD0F62990, slot = "MCR" },
  { name = "John McGinn",  addr = 0xD23F8840, slot = "MCL" },
  { name = "A. El Ghazi",  addr = 0xD1A47A60, slot = "AMR" },
  { name = "Jack Grealish",addr = 0xD0F80DF0, slot = "AML" },
  { name = "Ollie Watkins",addr = 0xD13E40E0, slot = "STC" },
}

-- Named subs, so a structure holding the full 18/19 is recognised too.
SUBS = {
  { name = "Jed Steer",    addr = 0xD0F31EB0 },
  { name = "K. Hause",     addr = 0xD129CD00 },
  { name = "Morgan Sanson",addr = 0xD2EBD8A0 },
  { name = "Keinan Davis", addr = 0xD0FE9410 },
  { name = "Neil Taylor",  addr = 0xD1256560 },
  { name = "Tom Heaton",   addr = 0xCF4FAAF0 },
  { name = "B. Traore",    addr = 0xD0B1D620 },
  { name = "Douglas Luiz", addr = 0xD0DA66E0 },
}

local STRIDES = { 8, 16, 24, 32, 40, 48, 64 }
local ANCHOR  = 11        -- Ollie Watkins; any starter works
local MIN_HIT = 5         -- report anything this good

local starterByAddr, subByAddr = {}, {}
for _, p in ipairs(STARTERS) do starterByAddr[p.addr] = p end
for _, p in ipairs(SUBS)     do subByAddr[p.addr]     = p end

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function qwordAob(v)
  local b = {}
  for i = 0, 7 do b[#b+1] = string.format("%02X", (v >> (i*8)) & 0xFF) end
  return table.concat(b, " ")
end

-- How many starters (and subs) land on a grid of this stride through `hit`?
local function scoreGrid(hit, stride)
  local seen, list, nSub = {}, {}, 0
  for i = -25, 25 do
    local a = hit + i*stride
    local v = rq(a)
    if v then
      local s = starterByAddr[v]
      local u = subByAddr[v]
      if s and not seen[v] then
        seen[v] = true
        list[#list+1] = { i = i, addr = a, name = s.name, slot = s.slot }
      elseif u and not seen[v] then
        seen[v] = true
        nSub = nSub + 1
        list[#list+1] = { i = i, addr = a, name = u.name, slot = "sub" }
      end
    end
  end
  local nStart = 0
  for _, e in ipairs(list) do if e.slot ~= "sub" then nStart = nStart + 1 end end
  return nStart, nSub, list
end

function find_lineup()
  logf = io.open(LOG, "w")
  local anchor = STARTERS[ANCHOR]
  say(string.format("find_lineup: scanning for pointers to %s (%X)",
    anchor.name, anchor.addr))

  local ok, res = pcall(AOBScan, qwordAob(anchor.addr), "+W")
  if not ok or not res then
    say("  scan returned nothing (AOBScan gives nil on zero hits): " .. tostring(res))
    if logf then logf:close(); logf = nil end
    return
  end
  say(string.format("  %d hit(s); testing %d strides around each", res.Count, #STRIDES))

  local best, results, reported = { n = 0 }, {}, 0
  for i = 0, res.Count - 1 do
    local hit = tonumber("0x" .. res[i])
    for _, stride in ipairs(STRIDES) do
      local nStart, nSub, list = scoreGrid(hit, stride)
      if nStart > best.n then
        best = { n = nStart, nSub = nSub, hit = hit, stride = stride, list = list }
      end
      if nStart >= MIN_HIT and reported < 15 then
        reported = reported + 1
        say(string.format("\n  CANDIDATE hit=%X stride=%d -> %d/11 starters, %d subs",
          hit, stride, nStart, nSub))
        for _, e in ipairs(list) do
          say(string.format("    [%+3d] %X  %-14s %s", e.i, e.addr, e.name, e.slot))
        end
        results[#results+1] = string.format(
          '{"hit":"%X","stride":%d,"starters":%d,"subs":%d}', hit, stride, nStart, nSub)
      end
    end
  end
  res.destroy()

  if reported == 0 then
    say(string.format("\nNothing reached %d/11 starters.", MIN_HIT))
    if best.n > 0 then
      say(string.format("Best was %d/11 (+%d subs) at hit=%X stride=%d:",
        best.n, best.nSub or 0, best.hit, best.stride))
      for _, e in ipairs(best.list) do
        say(string.format("    [%+3d] %X  %-14s %s", e.i, e.addr, e.name, e.slot))
      end
    end
  end

  local f = io.open(OUT, "w")
  if f then f:write('{"candidates":[' .. table.concat(results, ",") .. ']}'); f:close() end
  if logf then logf:close(); logf = nil end
  realprint("find_lineup: full output in " .. LOG)
end
