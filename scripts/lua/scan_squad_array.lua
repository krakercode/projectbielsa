-- Phase 1 exploration: find the structure that holds the squad.
--
-- Takes the player record addresses collected by probe_watch.lua and scans
-- fm.exe's memory for qwords equal to those addresses -- i.e. every place in
-- memory holding a pointer to a known player. The squad list's backing array
-- should show up as a place where pointers to SEVERAL known Villa players sit
-- close together.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\scan_squad_array.lua]])
--   scan_squad()
--
-- Writes every hit to data/snapshots/ptr_hits.json for offline analysis and
-- prints a short summary. Scanning is done with CE's own scan engine rather
-- than a hand-rolled region walk so it stays fast on a multi-GB process.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\ptr_hits.json]]
local LOG = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\ptr_hits.log]]

-- Known Villa player records, from probe_watch.lua. name = record address.
local TARGETS = {
  { name = "Grealish", addr = 0xAFC7E370, rowid = 9230 },
  { name = "Heaton",   addr = 0xAFC8E710, rowid = 5052 },
  { name = "Martinez", addr = 0xAE6F7480, rowid = 7443 },
  { name = "Steer",    addr = 0xAFCBCB30, rowid = 8803 },
  { name = "Mings",    addr = 0xAFC8A910, rowid = 11424 },
  { name = "Hause",    addr = 0xAFCA66B0, rowid = 11502 },
  { name = "Cash",     addr = 0xAFC93490, rowid = 12195 },
  { name = "Konsa",    addr = 0xAFC909F0, rowid = 12127 },
}

local lines = {}
local function log(s)
  lines[#lines + 1] = tostring(s)
  print(s)
end

local function writeFile(path, contents)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(contents)
  f:close()
  return true
end

-- Scan the whole address space for an exact qword value; returns a list of
-- addresses (numbers) holding it.
local function scanForQword(value)
  local ms = createMemScan()
  ms.firstScan(
    soExactValue, vtQword, rtRounded,
    string.format("%X", value), nil,
    0, 0x7fffffffffff,
    "*X*C*W",           -- protection: don't care
    fsmAligned, "8",    -- pointers are 8-byte aligned
    true,               -- input is hexadecimal
    false, false, false)
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

function scan_squad()
  lines = {}
  local results = {}

  for _, t in ipairs(TARGETS) do
    local ok, hits = pcall(scanForQword, t.addr)
    if not ok then
      log("SCAN FAILED for " .. t.name .. ": " .. tostring(hits))
      hits = {}
    end
    results[t.name] = hits
    log(string.format("%s (%X): %d pointer(s)", t.name, t.addr, #hits))
  end

  -- Serialize hits for offline analysis.
  local parts = {}
  for _, t in ipairs(TARGETS) do
    local hs = {}
    for _, a in ipairs(results[t.name] or {}) do
      hs[#hs + 1] = string.format('"%X"', a)
    end
    parts[#parts + 1] = string.format('"%s":{"addr":"%X","rowid":%d,"hits":[%s]}',
      t.name, t.addr, t.rowid, table.concat(hs, ","))
  end
  writeFile(OUT, "{" .. table.concat(parts, ",") .. "}")
  log("wrote " .. OUT)

  writeFile(LOG, table.concat(lines, "\n") .. "\n")
end
