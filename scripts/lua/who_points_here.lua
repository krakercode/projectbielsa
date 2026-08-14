-- Phase 1 exploration: given an address, find every qword in fm.exe's memory
-- that holds it -- i.e. who references this object/array.
--
-- Used to walk *up* from the squad arrays (found by scan_squad_array.lua +
-- inspect_array.lua) toward an owning container, and eventually toward a
-- stable anchor we can resolve from cold instead of hardcoding heap addresses.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\who_points_here.lua]])
--   who_points_here({"9C3ED6F0", "6CB31240", "8C7F2220"})
--
-- Writes data/snapshots/refs.json.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\refs.json]]

local function scanForQword(value)
  local ms = createMemScan()
  ms.firstScan(
    soExactValue, vtQword, rtRounded,
    string.format("%X", value), nil,
    0, 0x7fffffffffff,
    "*X*C*W",
    fsmAligned, "8",
    true, false, false, false)
  ms.waitTillDone()
  local fl = createFoundList(ms)
  fl.initialize()
  local out = {}
  for i = 0, fl.Count - 1 do
    out[#out + 1] = tonumber(fl.Address[i], 16)
  end
  fl.destroy()
  ms.destroy()
  return out
end

function who_points_here(addrHexList)
  local parts = {}
  for _, hex in ipairs(addrHexList) do
    local target = tonumber(hex, 16)
    local ok, hits = pcall(scanForQword, target)
    if not ok then
      print("scan failed for " .. hex .. ": " .. tostring(hits))
      hits = {}
    end
    print(string.format("%s: %d referrer(s)", hex, #hits))

    local hs = {}
    for _, a in ipairs(hits) do
      -- Include a little context: the qwords either side of the referrer,
      -- which is usually where a count / end-pointer lives.
      local function rq(x)
        local o, v = pcall(readQword, x)
        return (o and v) and string.format("%X", v) or "?"
      end
      hs[#hs + 1] = string.format('{"at":"%X","prev":"%s","next":"%s","next2":"%s"}',
        a, rq(a - 8), rq(a + 8), rq(a + 16))
      print(string.format("    %X   prev=%s next=%s next2=%s",
        a, rq(a - 8), rq(a + 8), rq(a + 16)))
    end
    parts[#parts + 1] = string.format('"%s":[%s]', hex, table.concat(hs, ","))
  end

  local f = io.open(OUT, "w")
  if f then f:write("{" .. table.concat(parts, ",") .. "}") f:close() end
  print("wrote " .. OUT)
end
