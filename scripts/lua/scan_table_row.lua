-- Phase 1: find a league-table row by its contents, via AOB scan.
--
-- Previous attempts keyed on proximity to a Club* pointer and found nothing.
-- The 100-byte-stride runs left by the played 3->4 scan turned out to contain
-- no club pointer at all, and are most likely per-player appearance counters
-- (players who featured also went 3->4).
--
-- So stop assuming the row references its club by pointer -- it may hold a club
-- UID, or be reachable only from the competition object. Instead find the row
-- by its VALUES: Aston Villa's record on 4 Oct 2020 is P4 W2 D1 L1, which as a
-- run of little-endian integers is a distinctive byte pattern.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\scan_table_row.lua]])
--   scan_table_row()
--
-- Writes data/snapshots/table_row_scan.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUT = REPO .. [[\data\snapshots\table_row_scan.json]]

-- Aston Villa, 4 Oct 2020: P4 W2 D1 L1 GD-1 Pts7.
local VILLA = 0x975AA370
local PATTERNS = {
  { label = "int32 P,W,D,L", aob = "04 00 00 00 02 00 00 00 01 00 00 00 01 00 00 00" },
  { label = "int16 P,W,D,L", aob = "04 00 02 00 01 00 01 00" },
  { label = "int8  P,W,D,L", aob = "04 02 01 01" },
}

local MAX_REPORT = 40

local function rq(a)
  local ok, v = pcall(readQword, a)
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
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return nil end
  local q = rq(p + 0xB8)
  return q and readStr(q + 0x4) or nil
end

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function scan_table_row()
  local uid = r32(VILLA + 0xC)
  local rowid = r32(VILLA + 0x8)
  print(string.format("scan_table_row: Aston Villa %X -> '%s', rowId=%s uid=%s",
    VILLA, tostring(clubName(VILLA)), tostring(rowid), tostring(uid)))

  local out = {}
  for _, pat in ipairs(PATTERNS) do
    local ok, res = pcall(AOBScan, pat.aob)
    if not ok or res == nil then
      print(string.format("  %-16s no hits", pat.label))
    else
      local n = res.Count
      print(string.format("  %-16s %d hit(s)", pat.label, n))
      for i = 0, math.min(n, MAX_REPORT) - 1 do
        local a = tonumber(res[i], 16)
        -- Is the club identifiable near this row? Try a pointer, then the UID.
        local nearClub, how = nil, nil
        for off = -128, 128, 8 do
          local nm = clubName(rq(a + off))
          if nm then nearClub, how = nm, string.format("ptr%+d", off) break end
        end
        if not nearClub then
          for off = -128, 128, 4 do
            if r32(a + off) == uid then nearClub, how = "Aston Villa", string.format("uid%+d", off) break end
            if r32(a + off) == rowid then nearClub, how = "Aston Villa", string.format("rowid%+d", off) break end
          end
        end
        if nearClub then
          print(string.format("     %X  <- %s (%s)", a, nearClub, how))
        end
        out[#out + 1] = string.format('{"pattern":"%s","at":"%X","club":%s,"how":%s}',
          jesc(pat.label), a,
          nearClub and ('"' .. jesc(nearClub) .. '"') or "null",
          how and ('"' .. jesc(how) .. '"') or "null")
      end
      res.destroy()
    end
  end

  local f = io.open(OUT, "w")
  if f then f:write('{"hits":[' .. table.concat(out, ",") .. ']}') f:close() end
  print("scan_table_row: wrote " .. OUT)
end
