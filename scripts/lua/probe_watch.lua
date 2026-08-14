-- Dev helper: watch pCurrentPlayer and log every distinct player record the
-- game selects, so you can click through a squad in FM in one pass and
-- collect all their record addresses without switching back to Cheat Engine
-- between each one.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_watch.lua]])
--   probe_watch_start()   -- then go click through players in FM
--   probe_watch_stop()    -- back in CE when done
--
-- Appends one JSON line per newly-seen player to
-- data/snapshots/probe.jsonl (same format as probe_player.lua).

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\probe.jsonl]]

local seen = {}
local timer = nil
local count = 0

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok then return s end
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

local function sample()
  local ok, err = pcall(function()
    local sym = getAddress("pCurrentPlayer")
    if not sym or sym == 0 then return end
    local base = readQword(sym)
    if base == nil or base == 0 then return end
    if seen[base] then return end
    seen[base] = true

    local line = string.format(
      '{"addr":"%X","addr_dec":%d,"rowid":%d,"uid":%d,"first":"%s","last":"%s","ca":%d,"club":"%s"}',
      base, base,
      readInteger(base + 0x278) or -1,
      readInteger(base + 0x27C) or -1,
      tostring(readStr(chain(base, { 0x2C8, 0x0, 0x4 }))),
      tostring(readStr(chain(base, { 0x2D0, 0x0, 0x4 }))),
      readSmallInteger(base + 0x1FC) or -1,
      tostring(readStr(chain(base, { 0x88, 0x30, 0xB8, 0x4 }))))

    local f = io.open(OUT, "a")
    if f then
      f:write(line .. "\n")
      f:close()
    end
    count = count + 1
    print("[" .. count .. "] " .. line)
  end)
  if not ok then print("probe_watch error: " .. tostring(err)) end
end

function probe_watch_start()
  if timer then print("probe_watch: already running") return end
  seen = {}
  count = 0
  timer = createTimer(nil)
  timer.Interval = 400
  timer.OnTimer = sample
  timer.Enabled = true
  print("probe_watch: started -- click through players in FM, then probe_watch_stop()")
end

function probe_watch_stop()
  if timer then
    timer.Enabled = false
    timer.Destroy()
    timer = nil
  end
  print("probe_watch: stopped after " .. count .. " distinct players")
end
