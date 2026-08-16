-- Record every writable location currently holding a given pointer value.
--
-- PURPOSE
-- Team selection is not a field on the player record -- swapping a starter for a
-- sub changed zero bytes across all 23 player records. So the XI is a structure
-- holding player POINTERS. To find WHICH slot encodes "starts at DL", take the
-- set of locations holding player X's pointer while X is starting, then swap X
-- out and take it again. Slots that disappear are the ones that meant
-- "X is selected"; everything else is squad lists, UI caches and coincidence.
--
-- This is deliberately one AOBScan per call and nothing else. (Nesting an
-- AOBScan inside a result loop once blocked CE's single-threaded Lua engine for
-- ~25 minutes with no way to interrupt it -- don't repeat that.)
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\scan_ptr.lua]])
--   scan_ptr("D0F909D0", "targett_starting")
--   -- ... change the lineup in FM ...
--   scan_ptr("D0F909D0", "targett_benched")
-- then diff the two JSON files offline.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]

local function qwordAob(v)
  local b = {}
  for i = 0, 7 do b[#b+1] = string.format("%02X", (v >> (i*8)) & 0xFF) end
  return table.concat(b, " ")
end

-- Same idea for a 4-byte value. Needed because the pointer scan came back
-- inconclusive: the one heap slot that held a starter's pointer only while he
-- was selected turned out to be a UI property table (neighbouring qwords decode
-- as "widt", "name", ... interleaved with pointers), i.e. a widget cache rather
-- than the selection. FM may well store selection by player UID or squad index
-- instead of by pointer, which this tests directly.
function scan_u32(decValue, tag)
  tag = tag or "scan"
  local val = tonumber(decValue)
  if not val then print("scan_u32: bad value " .. tostring(decValue)) return end

  local out = REPO .. [[\data\snapshots\u32_]] .. tag .. ".json"
  local b = {}
  for i = 0, 3 do b[#b+1] = string.format("%02X", (val >> (i*8)) & 0xFF) end
  local aob = table.concat(b, " ")
  print(string.format("scan_u32: scanning for %d (0x%X) as 4 bytes  (tag '%s')", val, val, tag))

  local ok, res = pcall(AOBScan, aob, "+W")
  if not ok or not res then
    print("scan_u32: no hits")
    local f = io.open(out, "w")
    if f then f:write(string.format('{"value":%d,"tag":"%s","count":0,"hits":[]}', val, tag)); f:close() end
    return
  end
  local hits = {}
  for i = 0, res.Count - 1 do hits[#hits+1] = '"' .. res[i] .. '"' end
  local n = res.Count
  res.destroy()

  local f = io.open(out, "w")
  if not f then print("scan_u32: cannot write " .. out) return end
  f:write(string.format('{"value":%d,"tag":"%s","count":%d,"hits":[%s]}',
    val, tag, n, table.concat(hits, ",")))
  f:close()
  print(string.format("scan_u32: %d hit(s) -> %s", n, out))
end

-- Scan for an arbitrary byte pattern.
--
-- Motivation: the eleven copies of the selection list are serialized records with
-- inline display names. The authoritative store almost certainly is not -- it
-- should be a compact array of player UIDs in positional order. Two consecutive
-- starters' UIDs as an 8-byte pattern is a very selective probe for exactly that,
-- and it does not depend on knowing the record layout in advance.
function scan_aob(aob, tag)
  tag = tag or "aob"
  local out = REPO .. [[\data\snapshots\aob_]] .. tag .. ".json"
  print(string.format("scan_aob: scanning for '%s'  (tag '%s')", aob, tag))

  local ok, res = pcall(AOBScan, aob, "+W")
  if not ok or not res then
    print("scan_aob: no hits")
    local f = io.open(out, "w")
    if f then f:write(string.format('{"aob":"%s","tag":"%s","count":0,"hits":[]}', aob, tag)); f:close() end
    return
  end
  local hits = {}
  for i = 0, res.Count - 1 do hits[#hits+1] = '"' .. res[i] .. '"' end
  local n = res.Count
  res.destroy()

  local f = io.open(out, "w")
  if not f then print("scan_aob: cannot write " .. out) return end
  f:write(string.format('{"aob":"%s","tag":"%s","count":%d,"hits":[%s]}',
    aob, tag, n, table.concat(hits, ",")))
  f:close()
  print(string.format("scan_aob: %d hit(s) -> %s", n, out))
end

function scan_ptr(hexAddr, tag)
  tag = tag or "scan"
  local val = tonumber(hexAddr, 16)
  if not val then print("scan_ptr: bad address " .. tostring(hexAddr)) return end

  local out = REPO .. [[\data\snapshots\ptr_]] .. tag .. ".json"
  print(string.format("scan_ptr: scanning for qword %X  (tag '%s')", val, tag))

  local ok, res = pcall(AOBScan, qwordAob(val), "+W")
  if not ok or not res then
    print("scan_ptr: no hits (AOBScan returns nil on zero results)")
    local f = io.open(out, "w")
    if f then f:write(string.format('{"value":"%X","tag":"%s","count":0,"hits":[]}', val, tag)); f:close() end
    return
  end

  local hits = {}
  for i = 0, res.Count - 1 do
    hits[#hits+1] = '"' .. res[i] .. '"'
  end
  local n = res.Count
  res.destroy()

  local f = io.open(out, "w")
  if not f then print("scan_ptr: cannot write " .. out) return end
  f:write(string.format('{"value":"%X","tag":"%s","count":%d,"hits":[%s]}',
    val, tag, n, table.concat(hits, ",")))
  f:close()
  print(string.format("scan_ptr: %d hit(s) -> %s", n, out))
end
