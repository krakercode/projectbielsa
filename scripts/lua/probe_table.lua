-- Phase 1 exploration: find the league table row structure.
--
-- Blocked until now because the save was pre-season and every table cell was
-- zero, leaving nothing distinctive to scan for. With three match days played
-- each club has a unique-ish stat tuple, so we can find a row by its contents.
--
-- Method: scan for pointers to a known club record, then inspect the memory
-- around each hit looking for that club's league stats. Printing the
-- neighbourhood as integers lets us read the row layout directly rather than
-- guessing field order or width.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_table.lua]])
--   probe_table()
--
-- Writes data/snapshots/table_probe.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUT = REPO .. [[\data\snapshots\table_probe.json]]

-- Leicester, 3 Oct 2020: P3 W3 D0 L0 GD6 Pts9. Chosen because W3/L0/Pts9 with
-- GD6 is distinctive, and the club record address is known for this session.
local CLUB = { name = "Leicester", addr = 0x975B0478 }
local WANT = { played = 3, won = 3, drawn = 0, lost = 0, gd = 6, pts = 9 }

local BEFORE, AFTER = 64, 128   -- bytes either side of a hit to inspect
local MAX_REPORT = 12

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function r16(a)
  local ok, v = pcall(readSmallInteger, a)
  if ok then return v end
  return nil
end

local function r32(a)
  local ok, v = pcall(readInteger, a)
  if ok then return v end
  return nil
end

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok and s and #s > 0 then return s end
  return nil
end

local function clubName(p)
  local q = rq(p + 0xB8)
  return q and readStr(q + 0x4) or nil
end

local function scanForQword(value)
  local ms = createMemScan()
  ms.firstScan(soExactValue, vtQword, rtRounded, string.format("%X", value), nil,
    0, 0x7fffffffffff, "*X*C*W", fsmAligned, "8", true, false, false, false)
  ms.waitTillDone()
  local fl = createFoundList(ms)
  fl.initialize()
  local out = {}
  for i = 0, fl.Count - 1 do out[#out + 1] = tonumber(fl.Address[i], 16) end
  fl.destroy()
  ms.destroy()
  return out
end

-- Look for the played/won/drawn/lost sequence near `h`.
--
-- Deliberately NOT keyed on goal difference: GD is almost certainly derived
-- from goals-for minus goals-against rather than stored, and points may be
-- computed from W*3+D too. P/W/D/L are the fields a table must actually hold.
-- The first version of this searched for points+GD adjacency and found nothing
-- convincing, which is what prompted the change.
local function findSequence(h, seq, width)
  local reader = (width == 2) and r16 or r32
  local matches = {}
  for off = -BEFORE, AFTER - (#seq * width), width do
    local ok = true
    for i, want in ipairs(seq) do
      if reader(h + off + (i - 1) * width) ~= want then ok = false break end
    end
    if ok then matches[#matches + 1] = off end
  end
  return matches
end

local function looksLikeRow(h)
  local seq = { WANT.played, WANT.won, WANT.drawn, WANT.lost }
  local m16 = findSequence(h, seq, 2)
  if #m16 > 0 then return true, m16[1], 2 end
  local m32 = findSequence(h, seq, 4)
  if #m32 > 0 then return true, m32[1], 4 end
  return false
end

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function probe_table()
  local name = clubName(CLUB.addr)
  print(string.format("probe_table: %s at %X reads as '%s'", CLUB.name, CLUB.addr,
    tostring(name)))
  if name == nil then
    print("probe_table: club address is stale -- reopen a club page and re-harvest")
    return nil
  end

  local hits = scanForQword(CLUB.addr)
  print(string.format("probe_table: %d pointer(s) to %s", #hits, CLUB.name))

  -- Dump full windows to disk rather than the console: the CE output pane
  -- scrolls and truncates, which made the first attempt hard to read.
  local reported, out = 0, {}
  for _, h in ipairs(hits) do
    local ok, seqOff, width = looksLikeRow(h)
    if ok and reported < MAX_REPORT then
      reported = reported + 1
      print(string.format("--- hit %X: P/W/D/L found at %+d as %d-byte ints",
        h, seqOff, width))

      local vals16, vals32 = {}, {}
      for off = -BEFORE, AFTER, 2 do
        vals16[#vals16 + 1] = string.format('{"o":%d,"v":%s}', off, tostring(r16(h + off)))
      end
      for off = -BEFORE, AFTER, 4 do
        vals32[#vals32 + 1] = string.format('{"o":%d,"v":%s}', off, tostring(r32(h + off)))
      end
      out[#out + 1] = string.format(
        '{"hit":"%X","seqOffset":%d,"width":%d,"i16":[%s],"i32":[%s]}',
        h, seqOff, width, table.concat(vals16, ","), table.concat(vals32, ","))
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write(string.format('{"club":"%s","addr":"%X","want":{"p":%d,"w":%d,"d":%d,"l":%d,"gd":%d,"pts":%d},"candidates":[%s]}',
      jesc(CLUB.name), CLUB.addr, WANT.played, WANT.won, WANT.drawn, WANT.lost,
      WANT.gd, WANT.pts, table.concat(out, ",")))
    f:close()
  end
  print(string.format("probe_table: %d candidate row(s) -> %s", reported, OUT))
end
