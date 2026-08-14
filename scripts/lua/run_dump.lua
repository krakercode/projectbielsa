-- Dev helper: run from Cheat Engine's Lua Engine (Ctrl+Alt+L) with
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\run_dump.lua]])
--
-- Loads dump_state.lua, dumps the current selection to
-- data/snapshots/dump_test.json, and writes a status line (OK or the Lua
-- error) to data/snapshots/dump_test.log so failures are readable off-screen.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT = REPO .. [[\data\snapshots\dump_test.json]]
local LOG = REPO .. [[\data\snapshots\dump_test.log]]

local function writeFile(path, contents)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(contents)
  f:close()
  return true
end

local lines = {}
local function log(s)
  lines[#lines + 1] = tostring(s)
  print(s)
end

local ok, err = pcall(function()
  dofile(REPO .. [[\scripts\lua\dump_state.lua]])
  log("loaded dump_state.lua")

  -- Raw symbol resolution, before any offset math -- tells us whether the
  -- base table's globals exist at all vs. the offsets being wrong.
  for _, sym in ipairs({ "pCurrentPlayer", "pCurrentClub", "pCurrentStaff" }) do
    local okSym, addr = pcall(getAddress, sym)
    if okSym and addr and addr ~= 0 then
      local okVal, val = pcall(readQword, addr)
      log(string.format("%s: symbol=%X value=%s", sym, addr,
        (okVal and val) and string.format("%X", val) or tostring(val)))
    else
      log(sym .. ": symbol NOT FOUND")
    end
  end

  local json = dump_state_json()
  log("json length = " .. tostring(#json))
  if not writeFile(OUT, json) then error("could not write " .. OUT) end
  log("wrote " .. OUT)
end)

if not ok then log("ERROR: " .. tostring(err)) end
writeFile(LOG, table.concat(lines, "\n") .. "\n")
