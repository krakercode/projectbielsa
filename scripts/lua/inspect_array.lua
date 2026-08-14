-- Phase 1 exploration: given an address inside a suspected array of player
-- pointers, walk outwards and try to resolve every slot as a player record.
-- This is what turns "several known players' pointers sit near each other"
-- into "this is the squad array, it starts here and holds N players".
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\inspect_array.lua]])
--   inspect_array("9C3ED6F0", 8, 64, 128)   -- addr, stride, slots back, slots fwd
--   inspect_all()                            -- run over the candidates below
--
-- Writes data/snapshots/array_<addr>.json and prints a compact summary.

local OUTDIR = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\]]

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok and s and #s > 0 then return s end
  return nil
end

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

local function printable(s)
  if not s or #s == 0 then return false end
  for i = 1, #s do
    local b = s:byte(i)
    if b < 32 or b > 126 then return false end
  end
  return true
end

-- Try to interpret `p` as a player record. Returns a table or nil.
local function asPlayer(p)
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return nil end
  local okv, vt = pcall(readQword, p)
  if not okv or vt == nil or vt == 0 then return nil end

  local first = readStr(chain(p, { 0x2C8, 0x0, 0x4 }))
  local last = readStr(chain(p, { 0x2D0, 0x0, 0x4 }))
  if not (printable(first) or printable(last)) then return nil end

  local okca, ca = pcall(readSmallInteger, p + 0x1FC)
  if not okca or ca == nil or ca < 1 or ca > 200 then return nil end

  return {
    first = first or "",
    last = last or "",
    ca = ca,
    rowid = select(2, pcall(readInteger, p + 0x278)) or -1,
    uid = select(2, pcall(readInteger, p + 0x27C)) or -1,
    club = readStr(chain(p, { 0x88, 0x30, 0xB8, 0x4 })) or "",
  }
end

local function jesc(s)
  return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"')
end

function inspect_array(addrHex, stride, back, fwd)
  stride = stride or 8
  back = back or 64
  fwd = fwd or 128
  local center = tonumber(addrHex, 16)
  if not center then print("bad address: " .. tostring(addrHex)) return end

  local rows = {}
  local hits, misses, run, bestRun = 0, 0, 0, 0
  for i = -back, fwd do
    local slot = center + i * stride
    local okp, p = pcall(readQword, slot)
    local rec = okp and asPlayer(p) or nil
    if rec then
      hits = hits + 1
      run = run + 1
      if run > bestRun then bestRun = run end
      rows[#rows + 1] = string.format(
        '{"slot":"%X","i":%d,"ptr":"%X","first":"%s","last":"%s","ca":%d,"rowid":%d,"uid":%d,"club":"%s"}',
        slot, i, p, jesc(rec.first), jesc(rec.last), rec.ca, rec.rowid, rec.uid, jesc(rec.club))
    else
      misses = misses + 1
      run = 0
      rows[#rows + 1] = string.format('{"slot":"%X","i":%d,"ptr":"%s","player":null}',
        slot, i, okp and string.format("%X", p or 0) or "unreadable")
    end
  end

  local path = OUTDIR .. "array_" .. addrHex .. ".json"
  local f = io.open(path, "w")
  if f then
    f:write('{"center":"' .. addrHex .. '","stride":' .. stride ..
      ',"resolved":' .. hits .. ',"unresolved":' .. misses ..
      ',"longestRun":' .. bestRun .. ',"slots":[' .. table.concat(rows, ",") .. ']}')
    f:close()
  end
  print(string.format("%s stride=%d: %d resolved / %d slots, longest run %d -> %s",
    addrHex, stride, hits, hits + misses, bestRun, path))
end

-- Candidate cluster starts found by scan_squad_array.lua, with the stride
-- implied by the spacing of known players inside each.
function inspect_all()
  inspect_array("6CB31248", 8, 64, 192)
  inspect_array("9C3ED6F0", 8, 64, 192)
  inspect_array("B3FDB068", 8, 64, 192)
  inspect_array("CBDF1CE0", 16, 64, 192)
  inspect_array("CE44FBE8", 8, 64, 192)
  inspect_array("6DB1E68", 8, 64, 192)
end
