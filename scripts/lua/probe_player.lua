-- Dev helper: record the currently-selected player's raw record address plus
-- identifying fields, appending one JSON line per call to
-- data/snapshots/probe.jsonl.
--
-- Usage from Cheat Engine's Lua Engine, once per player:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_player.lua]])
-- then click a different player in FM and run it again.
--
-- Purpose: collect (address, rowID) pairs for several known players so we can
-- test whether player records live in one contiguous row-indexed array
-- (address = arrayBase + rowID * recordSize). If that holds, the whole
-- database is walkable without an AOB scan.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\probe.jsonl]]

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok then return s end
  return nil
end

-- Walk an offset chain in application order: addr = base + o1, then
-- addr = [addr] + oi for each subsequent offset.
local function chain(base, offsets)
  local addr = base
  for i, off in ipairs(offsets) do
    if i == 1 then
      addr = addr + off
    else
      local ok, ptr = pcall(readQword, addr)
      if not ok or ptr == nil or ptr == 0 then return nil end
      addr = ptr + off
    end
  end
  return addr
end

local sym = getAddress("pCurrentPlayer")
local base = readQword(sym)
if base == nil or base == 0 then
  print("probe: no player currently selected (pCurrentPlayer is 0)")
  return
end

local rec = {
  addr = base,
  rowid = readInteger(base + 0x278),
  uid = readInteger(base + 0x27C),
  first = readStr(chain(base, { 0x2C8, 0x0, 0x4 })),
  last = readStr(chain(base, { 0x2D0, 0x0, 0x4 })),
  ca = readSmallInteger(base + 0x1FC),
  club = readStr(chain(base, { 0x88, 0x30, 0xB8, 0x4 })),
}

local line = string.format(
  '{"addr":"%X","addr_dec":%d,"rowid":%d,"uid":%d,"first":"%s","last":"%s","ca":%d,"club":"%s"}',
  rec.addr, rec.addr, rec.rowid or -1, rec.uid or -1,
  tostring(rec.first), tostring(rec.last), rec.ca or -1, tostring(rec.club))

local f = io.open(OUT, "a")
if not f then
  print("probe: could not open " .. OUT)
  return
end
f:write(line .. "\n")
f:close()
print("probe: " .. line)
