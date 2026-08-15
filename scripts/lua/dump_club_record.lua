-- Phase 1 exploration: dump raw club-object memory so the league record fields
-- can be found by cross-referencing two clubs with different known records.
--
-- Rationale: searching near *pointers to* a club found nothing, so the P/W/D/L
-- figures are probably stored on the club object itself. Rather than guess an
-- offset, dump the same byte range from two clubs whose real-world records
-- differ, then look for the offset where club A reads as A's record and club B
-- reads as B's. One offset satisfying both is almost certainly the row.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_club_record.lua]])
--   dump_club_record()
--
-- Writes data/snapshots/club_records.json for offline analysis.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUT = REPO .. [[\data\snapshots\club_records.json]]
local RANGE = 0x2000   -- bytes of club object to dump

-- League table as of 3 Oct 2020, three match days played.
local CLUBS = {
  { name = "Leicester",   addr = 0x975B0478, p = 3, w = 3, d = 0, l = 0, gd = 6,  pts = 9 },
  { name = "Aston Villa", addr = 0x975AA370, p = 3, w = 1, d = 1, l = 1, gd = -2, pts = 4 },
  { name = "Man City",    addr = 0x975B0CE8, p = 3, w = 3, d = 0, l = 0, gd = 6,  pts = 9 },
  { name = "Everton",     addr = 0x975AE420, p = 3, w = 1, d = 2, l = 0, gd = 2,  pts = 5 },
}

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

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function dump_club_record()
  local parts = {}
  for _, c in ipairs(CLUBS) do
    local live = clubName(c.addr)
    print(string.format("dump_club_record: %-12s %X reads as '%s'", c.name, c.addr,
      tostring(live)))
    if live then
      local vals = {}
      for off = 0, RANGE - 2, 2 do
        vals[#vals + 1] = tostring(r16(c.addr + off) or "null")
      end
      parts[#parts + 1] = string.format(
        '{"name":"%s","addr":"%X","live":"%s","p":%d,"w":%d,"d":%d,"l":%d,"gd":%d,"pts":%d,"i16":[%s]}',
        jesc(c.name), c.addr, jesc(live), c.p, c.w, c.d, c.l, c.gd, c.pts,
        table.concat(vals, ","))
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write(string.format('{"range":%d,"clubs":[%s]}', RANGE, table.concat(parts, ",")))
    f:close()
  end
  print("dump_club_record: wrote " .. OUT)
end
