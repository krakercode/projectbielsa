-- Phase 1: decode league-table rows.
--
-- An iterative value scan (played 3 -> 4 across a match day) left survivors in
-- arithmetic runs with a 100-byte stride. Runs were 13-15 long rather than 20,
-- which is exactly right: clubs that did not play that match day stayed on 3,
-- so they drop out and break the run. That makes 100 bytes the league-table row
-- size and the survivor address the offset of the "played" field within a row.
--
-- This walks rows at that stride and, for each, finds the Club* inside the row
-- and prints the integers around it, so the field layout can be read directly.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_table_rows.lua]])
--   dump_table_rows("CFBADF4C")             -- address of a 'played' field
--   dump_table_rows("CFBADF4C", 100, 24)    -- stride, rows either side
--
-- Writes data/snapshots/table_rows.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUTDIR = REPO .. [[\data\snapshots\]]

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

local function printable(s)
  if not s or #s == 0 then return false end
  for i = 1, #s do
    local b = s:byte(i)
    if b < 32 or b > 126 then return false end
  end
  return true
end

local function clubName(p)
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return nil end
  local vt = rq(p)
  if vt == nil or vt == 0 then return nil end
  local q = rq(p + 0xB8)
  local n = q and readStr(q + 0x4) or nil
  if not printable(n) then return nil end
  local q2 = rq(p + 0xC0)
  if not printable(q2 and readStr(q2 + 0x4) or nil) then return nil end
  return n
end

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function dump_table_rows(addrHex, stride, span)
  stride = stride or 100
  span = span or 24
  local anchor = tonumber(addrHex, 16)
  if not anchor then print("bad address") return nil end

  local rows = {}
  print(string.format("dump_table_rows: anchor %X, stride %d, +/-%d rows", anchor, stride, span))
  for k = -span, span do
    local fieldAddr = anchor + k * stride
    -- The row starts somewhere at or before the played field. Search the
    -- surrounding stride-sized region for the Club* that owns this row.
    local club, clubAt = nil, nil
    for off = -stride, stride, 8 do
      local a = fieldAddr + off
      if a % 8 == 0 then
        local n = clubName(rq(a))
        if n then club, clubAt = n, a break end
      end
    end
    if club then
      local ints = {}
      for off = 0, 24, 4 do ints[#ints + 1] = r32(fieldAddr + off) end
      print(string.format("  %+3d  %X  club=%-26s clubAt=%+4d  ints=%s",
        k, fieldAddr, club, clubAt - fieldAddr,
        table.concat({ tostring(ints[1]), tostring(ints[2]), tostring(ints[3]),
                       tostring(ints[4]), tostring(ints[5]), tostring(ints[6]),
                       tostring(ints[7]) }, ",")))
      local js = {}
      for i, v in ipairs(ints) do js[#js + 1] = tostring(v) end
      rows[#rows + 1] = string.format(
        '{"k":%d,"field":"%X","club":"%s","clubOffset":%d,"ints":[%s]}',
        k, fieldAddr, jesc(club), clubAt - fieldAddr, table.concat(js, ","))
    end
  end

  local path = OUTDIR .. "table_rows.json"
  local f = io.open(path, "w")
  if f then
    f:write(string.format('{"anchor":"%X","stride":%d,"rows":[%s]}',
      anchor, stride, table.concat(rows, ",")))
    f:close()
  end
  print(string.format("dump_table_rows: %d row(s) with a club -> %s", #rows, path))
end
