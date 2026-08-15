-- Find the competition-scoped club list, and from it the competition object.
--
-- WHERE THIS CAME FROM
-- watch_table_render.lua trapped the name-render instruction and logged which
-- club it ran for. Buried in the output is a run of EXACTLY the 20 Premier League
-- clubs in alphabetical order -- not the 65-club global alphabetical index found
-- in an earlier session. Something therefore walks a competition-scoped list of
-- 20 clubs, and that list is the closest thing to the competition object we have
-- ever had a handle on. (docs/phase1-notes.md: "Locate the competition object.
-- Never found ... Currently the biggest gap.")
--
-- The registers at the trapped instruction were identical for every club, so the
-- loop lives further up the call stack than the capture reached. Rather than
-- chase deeper frames, this searches memory directly for the array.
--
-- METHOD (v2). The first attempt scanned for two alphabetically adjacent club
-- pointers back to back, and found no run. That method was wrong: a 16-byte
-- adjacent-pair pattern can only match a stride-8 pointer array. If the league
-- table is an array of row structs -- {Club*, P, W, D, L, ...} -- then successive
-- club pointers are 24 or 32 bytes apart and the pair pattern can never hit,
-- which is precisely the layout we are looking for.
--
-- So instead: scan for ONE club pointer (a few hundred hits, as the earlier
-- session saw), then around each hit test a range of strides and count how many
-- of the 20 clubs land on the grid. That finds a club array at ANY stride, and
-- the winning stride is itself the row size.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\find_competition.lua]])
--   find_competition()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\competition.json]]
local LOG  = REPO .. [[\data\snapshots\competition.log]]

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

-- Captured live 2026-08-15 from watch_table_render.lua, alphabetical order,
-- which is the order the renderer walked them in.
PL_CLUBS = {
  { name = "Arsenal",                 addr = 0x975AA208 },
  { name = "Aston Villa",             addr = 0x975AA370 },
  { name = "Brighton and Hove Albion",addr = 0x975AB888 },
  { name = "Burnley",                 addr = 0x975ABE28 },
  { name = "Chelsea",                 addr = 0x975AC968 },
  { name = "Crystal Palace",          addr = 0x975ADA48 },
  { name = "Everton",                 addr = 0x975AE420 },
  { name = "Fulham",                  addr = 0x975AE9C0 },
  { name = "Leeds United",            addr = 0x975B01A8 },
  { name = "Leicester City",          addr = 0x975B0478 },
  { name = "Liverpool",               addr = 0x975B08B0 },
  { name = "Manchester City",         addr = 0x975B0CE8 },
  { name = "Manchester United",       addr = 0x975B0E50 },
  { name = "Newcastle United",        addr = 0x975B1990 },
  { name = "Sheffield United",        addr = 0x975B35B0 },
  { name = "Southampton",             addr = 0x975B3CB8 },
  { name = "Tottenham Hotspur",       addr = 0x975B51D0 },
  { name = "West Bromwich Albion",    addr = 0x975B58D8 },
  { name = "West Ham United",         addr = 0x975B5A40 },
  { name = "Wolverhampton Wanderers", addr = 0x975B6148 },
}

local STRIDES = { 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 72, 80, 96, 128 }
local MIN_CLUBS = 6      -- report anything this good, so a near miss still teaches us
local ANCHOR = 1         -- index into PL_CLUBS to scan for

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function qwordAob(v)
  local b = {}
  for i = 0, 7 do
    b[#b+1] = string.format("%02X", (v >> (i*8)) & 0xFF)
  end
  return table.concat(b, " ")
end

local addrToName = {}
for _, c in ipairs(PL_CLUBS) do addrToName[c.addr] = c.name end

-- Treat `hit` as ANY slot in a hypothetical array of the given stride, and count
-- how many of the 20 clubs land on that grid. Scanning outward in both
-- directions means the anchor club does not have to be the first row.
local function scoreGrid(hit, stride)
  local seenClub, best = {}, {}
  local lo, hi = nil, nil
  for i = -19, 19 do
    local a = hit + i*stride
    local v = rq(a)
    local nm = v and addrToName[v] or nil
    if nm and not seenClub[nm] then
      seenClub[nm] = true
      best[#best+1] = { i = i, addr = a, name = nm }
      if lo == nil or i < lo then lo = i end
      if hi == nil or i > hi then hi = i end
    end
  end
  return #best, best, lo, hi
end

function find_competition()
  logf = io.open(LOG, "w")
  say("find_competition: hunting the competition-scoped 20-club list")

  local anchor = PL_CLUBS[ANCHOR]
  say(string.format("\nscanning for pointers to %s (%X)", anchor.name, anchor.addr))
  local ok, res = pcall(AOBScan, qwordAob(anchor.addr), "+W")
  if not ok or not res then
    say("  scan failed: " .. tostring(res))
    if logf then logf:close(); logf = nil end
    return
  end
  say(string.format("  %d hit(s); testing %d strides around each",
    res.Count, #STRIDES))

  -- Keep the best scoring (base,stride) per stride so the log stays readable.
  local results, reported = {}, 0
  local bestOverall = { n = 0 }
  for i = 0, res.Count - 1 do
    local hit = tonumber("0x" .. res[i])
    for _, stride in ipairs(STRIDES) do
      local n, list, lo, hi = scoreGrid(hit, stride)
      if n > bestOverall.n then
        bestOverall = { n = n, hit = hit, stride = stride, list = list, lo = lo, hi = hi }
      end
      if n >= MIN_CLUBS and reported < 12 then
        reported = reported + 1
        local base = hit + lo*stride
        say(string.format("\n  CANDIDATE hit=%X stride=%d -> %d/20 clubs, base=%X",
          hit, stride, n, base))
        for _, e in ipairs(list) do
          say(string.format("    [%+3d] %X  %s", e.i, e.addr, e.name))
        end
        results[#results+1] = string.format(
          '{"hit":"%X","base":"%X","stride":%d,"found":%d}', hit, base, stride, n)
      end
    end
  end
  res.destroy()

  if reported == 0 then
    say(string.format("\nNothing reached %d/20 clubs at any stride.", MIN_CLUBS))
    if bestOverall.n > 0 then
      say(string.format("Best was %d/20 at hit=%X stride=%d:",
        bestOverall.n, bestOverall.hit, bestOverall.stride))
      for _, e in ipairs(bestOverall.list) do
        say(string.format("    [%+3d] %X  %s", e.i, e.addr, e.name))
      end
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write('{"arrays":[' .. table.concat(results, ",") .. ']}')
    f:close()
    say("\nfind_competition: wrote " .. OUT)
  end
  if logf then logf:close(); logf = nil end
  realprint("find_competition: full output in " .. LOG)
end
