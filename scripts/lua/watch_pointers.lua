-- Diagnostic: poll the base table's pCurrent* globals and log every change,
-- so you can browse FM freely and afterwards see exactly which screen made a
-- given pointer populate.
--
-- Written to answer a specific question: pCurrentClub stays 0 even with the
-- "Current Club" script enabled and the Club Info page open, so something more
-- specific triggers its hook. Rather than guess screen by screen, start this,
-- browse everywhere, then read the log.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\watch_pointers.lua]])
--   watch_start()    -- then go browse FM
--   watch_stop()     -- back in CE
--
-- Appends to data/snapshots/pointer_watch.log. Each line is a transition, so
-- correlate against what you clicked.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\pointer_watch.log]]
local SYMS = { "pCurrentPlayer", "pCurrentClub", "pCurrentStaff" }

local timer = nil
local last = {}
local ticks = 0

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok and s and #s > 0 then return s end
  return nil
end

-- Best-effort label so the log says WHAT populated, not just that something did.
local function label(sym, base)
  if base == nil or base == 0 then return "0" end
  local ok, name = pcall(function()
    if sym == "pCurrentClub" then
      -- club name lives at [[club + 0xB8] + 0x4]
      local p = rq(base + 0xB8)
      return p and readStr(p + 0x4) or nil
    else
      -- player/staff: last name via the standard chain
      local off = (sym == "pCurrentStaff") and 0x148 or 0x2D0
      local p = rq(base + off)
      if not p then return nil end
      local q = rq(p + 0x0)
      return q and readStr(q + 0x4) or readStr(p + 0x4)
    end
  end)
  return string.format("%X (%s)", base, (ok and name) and name or "?")
end

local function append(line)
  local f = io.open(OUT, "a")
  if f then f:write(line .. "\n") f:close() end
  print(line)
end

local function tick()
  ticks = ticks + 1
  for _, sym in ipairs(SYMS) do
    local okSym, s = pcall(getAddress, sym)
    if okSym and s and s ~= 0 then
      local v = rq(s)
      if v ~= last[sym] then
        append(string.format("[tick %d] %s: %s -> %s", ticks, sym,
          last[sym] and label(sym, last[sym]) or "nil", label(sym, v)))
        last[sym] = v
      end
    end
  end
end

function watch_start()
  if timer then print("watch: already running") return end
  last = {}
  ticks = 0
  append("=== watch_start ===")
  timer = createTimer(nil)
  timer.Interval = 400
  timer.OnTimer = tick
  timer.Enabled = true
  print("watch: started -- browse FM, then watch_stop()")
end

function watch_stop()
  if timer then
    timer.Enabled = false
    timer.Destroy()
    timer = nil
  end
  append("=== watch_stop after " .. ticks .. " ticks ===")
end
