-- Export Cheat Engine's CURRENT scan results to disk for offline analysis.
--
-- Used after an iterative value scan (e.g. "was 3, now 4" across a match day)
-- to get the surviving addresses out of the GUI and into something we can look
-- for structure in -- regular strides, clustering, proximity to club pointers.
--
-- IMPORTANT: this reads the existing result set. It does not start a new scan,
-- so the GUI results stay intact.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\export_foundlist.lua]])
--   export_foundlist()
--
-- Writes data/snapshots/foundlist.json.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\foundlist.json]]

function export_foundlist()
  local ms = getCurrentMemscan()
  if ms == nil then
    print("export_foundlist: no active memory scan")
    return nil
  end
  local fl = createFoundList(ms)
  fl.initialize()
  local n = fl.Count
  print(string.format("export_foundlist: %d result(s)", n))

  local parts = {}
  for i = 0, n - 1 do
    parts[#parts + 1] = '"' .. fl.Address[i] .. '"'
  end
  fl.destroy()

  local f = io.open(OUT, "w")
  if not f then print("export_foundlist: could not write " .. OUT) return nil end
  f:write('{"count":' .. n .. ',"addresses":[' .. table.concat(parts, ",") .. ']}')
  f:close()
  print("export_foundlist: wrote " .. OUT)
  return n
end
