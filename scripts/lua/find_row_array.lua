-- Find the container that holds the per-club structures seen on the table render
-- path, and from it the competition object.
--
-- CHAIN OF REASONING SO FAR
-- 1. watch_table_render.lua trapped the club-name render instruction; during a
--    league-table render it fires once for each of the 20 Premier League clubs,
--    alphabetically, all at the SAME RSP -- so a single loop over a
--    competition-scoped collection of 20 clubs.
-- 2. Stack slot 10 held a distinct pointer per club into the CA22xxxx region,
--    monotonically increasing in club order: a parallel per-club structure.
-- 3. Those structures are NOT a fixed-stride array -- the gaps between them vary
--    (184, 2760, 736, ...), so each is individually heap-allocated.
--
-- Therefore whatever the loop walks must hold POINTERS to them. This scans for
-- such an array. Finding it gives the competition's club collection; whatever
-- points at that array is the competition object -- the thing phase1-notes calls
-- "the biggest gap".
--
-- This is the same scan shape as find_competition.lua but aimed at the CA22xxxx
-- objects rather than the club objects, because it is those the loop walks.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\find_row_array.lua]])
--   find_row_array()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\row_array.json]]
local LOG  = REPO .. [[\data\snapshots\row_array.log]]

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

-- stack[10] per club, alphabetical, from data/snapshots/table_render.json
ROW_OBJ = {
  { club = "Arsenal",        addr = 0xCA2243D0 },
  { club = "Aston Villa",    addr = 0xCA224488 },
  { club = "Brighton",       addr = 0xCA224F50 },
  { club = "Burnley",        addr = 0xCA225230 },
  { club = "Chelsea",        addr = 0xCA2257F0 },
  { club = "Crystal Palace", addr = 0xCA226090 },
  { club = "Everton",        addr = 0xCA226598 },
  { club = "Fulham",         addr = 0xCA226878 },
  { club = "Leeds",          addr = 0xCA2274B0 },
  { club = "Leicester",      addr = 0xCA227620 },
  { club = "Liverpool",      addr = 0xCA227848 },
  { club = "Man City",       addr = 0xCA227A70 },
  { club = "Man Utd",        addr = 0xCA227B28 },
  { club = "Newcastle",      addr = 0xCA2280E8 },
  { club = "Sheff Utd",      addr = 0xCA228F48 },
  { club = "Southampton",    addr = 0xCA2292E0 },
  { club = "Tottenham",      addr = 0xCA229DA8 },
  { club = "West Brom",      addr = 0xCA22A140 },
  { club = "West Ham",       addr = 0xCA22A1F8 },
  { club = "Wolves",         addr = 0xCA22A590 },
}

local STRIDES = { 8, 16, 24, 32, 40, 48, 64 }
local ANCHOR  = 1

local byAddr = {}
for _, r in ipairs(ROW_OBJ) do byAddr[r.addr] = r.club end

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

local function scoreGrid(hit, stride)
  local seenC, list, lo = {}, {}, nil
  for i = -19, 19 do
    local a = hit + i*stride
    local v = rq(a)
    local nm = v and byAddr[v] or nil
    if nm and not seenC[nm] then
      seenC[nm] = true
      list[#list+1] = { i = i, addr = a, name = nm }
      if lo == nil or i < lo then lo = i end
    end
  end
  return #list, list, lo
end

function find_row_array()
  logf = io.open(LOG, "w")
  local anchor = ROW_OBJ[ANCHOR]
  say(string.format("find_row_array: scanning for pointers to %s's row object (%X)",
    anchor.club, anchor.addr))

  local ok, res = pcall(AOBScan, qwordAob(anchor.addr), "+W")
  if not ok or not res then
    say("  scan failed: " .. tostring(res))
    if logf then logf:close(); logf = nil end
    return
  end
  say(string.format("  %d hit(s)", res.Count))

  local best = { n = 0 }
  local results = {}
  for i = 0, res.Count - 1 do
    local hit = tonumber("0x" .. res[i])
    for _, stride in ipairs(STRIDES) do
      local n, list, lo = scoreGrid(hit, stride)
      if n > best.n then best = { n = n, hit = hit, stride = stride, list = list, lo = lo } end
      if n >= 15 then
        local base = hit + lo*stride
        say(string.format("\n  ARRAY FOUND hit=%X stride=%d -> %d/20, base=%X",
          hit, stride, n, base))
        for _, e in ipairs(list) do
          say(string.format("    [%+3d] %X  %s", e.i, e.addr, e.name))
        end
        results[#results+1] = string.format('{"base":"%X","stride":%d,"found":%d}',
          base, stride, n)
        say("    who points at this array:")
        local ok2, res2 = pcall(AOBScan, qwordAob(base), "+W")
        if ok2 and res2 then
          say(string.format("      %d referrer(s)", res2.Count))
          for k = 0, math.min(res2.Count, 12) - 1 do
            local owner = tonumber("0x" .. res2[k])
            say(string.format("      owner slot %X  (container/competition candidate)", owner))
          end
          res2.destroy()
        end
      end
    end
  end
  res.destroy()

  if #results == 0 then
    say(string.format("\nNo array reached 15/20. Best was %d/20 (hit=%X stride=%d)",
      best.n, best.hit or 0, best.stride or 0))
    if best.list then
      for _, e in ipairs(best.list) do
        say(string.format("    [%+3d] %X  %s", e.i, e.addr, e.name))
      end
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write('{"arrays":[' .. table.concat(results, ",") .. ']}')
    f:close()
  end
  if logf then logf:close(); logf = nil end
  realprint("find_row_array: full output in " .. LOG)
end
