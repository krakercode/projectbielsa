-- Dump the per-club structures found on the league-table render path.
--
-- WHERE THESE ADDRESSES CAME FROM
-- watch_table_render.lua broke on the club-name render instruction and captured
-- 48 stack qwords per call. During the run of exactly the 20 Premier League clubs
-- (alphabetical, one call each, RSP identical at 811ECF0 so it is a single loop),
-- stack slot 10 held a DIFFERENT pointer for every club, monotonically increasing,
-- in the CA22xxxx region -- nowhere near the club objects at 975Axxxx.
--
-- One per club, in club order, allocated in parallel with the clubs. That is the
-- shape a league-table row has. This dumps raw bytes from each so the P/W/D/L/Pts
-- offsets can be found offline by matching against the real table, rather than by
-- guessing offsets in the game.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_league_rows.lua]])
--   dump_league_rows()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\league_rows.json]]

local RANGE = 0x400   -- bytes per candidate row

-- Two per-club pointer series were seen on the render path. Both are dumped so
-- they can be tested against the real table offline.
--
--   CA22xxxx  stack[10], the immediate frame. TESTED AND RULED OUT: no P/W/D/L/Pts
--             at any offset in the first 0x400 at width 1/2/4; the vector at
--             +0x10 has sizes (0..69) unrelated to matches played.
--   BBD9xxxx  stack[77]/[102]/[115], the CALLER frames -- closer to the loop, so
--             a better candidate for the row the table is built from.
ROWS_CA22 = {
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

ROWS_BBD9 = {
  { club = "Arsenal",        addr = 0xBBD953F8 },
  { club = "Aston Villa",    addr = 0xBBD954B0 },
  { club = "Brighton",       addr = 0xBBD95F78 },
  { club = "Burnley",        addr = 0xBBD96258 },
  { club = "Chelsea",        addr = 0xBBD96818 },
  { club = "Crystal Palace", addr = 0xBBD970B8 },
  { club = "Everton",        addr = 0xBBD975C0 },
  { club = "Fulham",         addr = 0xBBD978A0 },
  { club = "Leeds",          addr = 0xBBD984D8 },
  { club = "Leicester",      addr = 0xBBD98648 },
  { club = "Liverpool",      addr = 0xBBD98870 },
  { club = "Man City",       addr = 0xBBD98A98 },
  { club = "Man Utd",        addr = 0xBBD98B50 },
  { club = "Newcastle",      addr = 0xBBD99110 },
  { club = "Sheff Utd",      addr = 0xBBD99F70 },
  { club = "Southampton",    addr = 0xBBD9A308 },
  { club = "Tottenham",      addr = 0xBBD9ADD0 },
  { club = "West Brom",      addr = 0xBBD9B168 },
  { club = "West Ham",       addr = 0xBBD9B220 },
  { club = "Wolves",         addr = 0xBBD9B5B8 },
}

-- The sub-object each BBD9 record points at via +0x38. BBD9+0x30 is the club
-- pointer, confirmed for all 20, so these records really are per-club
-- competition entries -- the stats simply are not in their first 0x400.
ROWS_SUB = {
  { club = "Arsenal",        addr = 0xC2886C20 },
  { club = "Aston Villa",    addr = 0xDAD71A50 },
  { club = "Brighton",       addr = 0xA6091090 },
  { club = "Burnley",        addr = 0xC21354C0 },
  { club = "Chelsea",        addr = 0xCD4A1A40 },
  { club = "Crystal Palace", addr = 0xA5E73B30 },
  { club = "Everton",        addr = 0xC2D5E0B0 },
  { club = "Fulham",         addr = 0xD6F8CFF0 },
  { club = "Leeds",          addr = 0xA635DCB0 },
  { club = "Leicester",      addr = 0xA60AFF40 },
  { club = "Liverpool",      addr = 0xA635E030 },
  { club = "Man City",       addr = 0xC2D65130 },
  { club = "Man Utd",        addr = 0xC2D667B0 },
  { club = "Newcastle",      addr = 0xDB2B82A0 },
  { club = "Sheff Utd",      addr = 0xA635E570 },
  { club = "Southampton",    addr = 0xCD4DA2C0 },
  { club = "Tottenham",      addr = 0xC296F7D0 },
  { club = "West Brom",      addr = 0xD41DCA70 },
  { club = "West Ham",       addr = 0xDAD659D0 },
  { club = "Wolves",         addr = 0xDAD68A90 },
}

ROWS = ROWS_BBD9

local function rb(a)
  local ok, v = pcall(readBytes, a, 1, false)
  if ok and v then return v end
  return nil
end

function dump_league_rows(which)
  ROWS = (which == "CA22" and ROWS_CA22)
      or (which == "SUB"  and ROWS_SUB)
      or ROWS_BBD9
  local parts = {}
  local live = 0
  for _, r in ipairs(ROWS) do
    local bytes = {}
    local ok = true
    for off = 0, RANGE - 1 do
      local b = rb(r.addr + off)
      if b == nil then ok = false; b = 0 end
      bytes[#bytes+1] = tostring(b)
    end
    if ok then live = live + 1 end
    print(string.format("dump_league_rows: %-16s %X  readable=%s",
      r.club, r.addr, tostring(ok)))
    parts[#parts+1] = string.format('{"club":"%s","addr":"%X","readable":%s,"bytes":[%s]}',
      r.club, r.addr, tostring(ok), table.concat(bytes, ","))
  end

  local f = io.open(OUT, "w")
  if not f then print("dump_league_rows: cannot write " .. OUT) return end
  f:write(string.format('{"range":%d,"rows":[%s]}', RANGE, table.concat(parts, ",")))
  f:close()
  print(string.format("dump_league_rows: wrote %s (%d/%d fully readable)",
    OUT, live, #ROWS))
end
