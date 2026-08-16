-- Break when something WRITES to an address, and record who did it.
--
-- WHY
-- The selected XI is readable (scripts/manager/read_lineup.js), but the structure
-- it reads is one of ELEVEN identical copies carrying inline display names -- a UI
-- data model, not the canonical tactic object. Writing into it would very likely
-- change only what is drawn.
--
-- Whatever code POPULATES those copies must be reading the authoritative store.
-- So: put a write breakpoint on one copy's player-UID slot, change the lineup in
-- FM, and inspect the registers at the moment of the write. One of them should
-- point into the real selection structure.
--
-- This is bptWrite, not bptAccess: reads of that slot happen constantly (every
-- render), whereas writes happen only when the selection actually changes, which
-- is exactly the event we care about. Using bptAccess here would bury the signal.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\watch_write.lua]])
--   watch_write("DF9B0711")     -- the DL slot in one copy of the selection list
--   -- ... swap the DL player in FM ...
--   stop_write()
--   dump_write()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\write_watch.json]]

local MAX_RECORDS = 300
local MAX_TOTAL   = 20000
local STACK_DEPTH = 64

local st = nil

local function hx(v) if not v then return "0" end return string.format("%X", v) end

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

function debugger_onBreakpoint()
  if not st or not st.active then return 1 end
  pcall(function()
    st.total = st.total + 1
    if st.total > MAX_TOTAL then
      st.active = false
      pcall(debug_removeBreakpoint, st.addr)
      return
    end
    if #st.records >= MAX_RECORDS then return end
    local stack = {}
    for i = 0, STACK_DEPTH - 1 do stack[#stack+1] = rq(RSP + i*8) end
    st.records[#st.records+1] = {
      n = st.total, rip = RIP,
      regs = { RAX=RAX, RBX=RBX, RCX=RCX, RDX=RDX, RSI=RSI, RDI=RDI,
               RBP=RBP, RSP=RSP, R8=R8, R9=R9, R10=R10, R11=R11,
               R12=R12, R13=R13, R14=R14, R15=R15 },
      stack = stack,
    }
  end)
  return 1
end

function watch_write(hexAddr, size)
  local addr = tonumber(hexAddr, 16)
  if not addr then print("watch_write: bad address " .. tostring(hexAddr)) return end
  st = { active = true, total = 0, records = {}, addr = addr }

  local ok, err = pcall(debug_setBreakpoint, addr, size or 4, bptWrite)
  if not ok then
    print("watch_write: FAILED to set breakpoint: " .. tostring(err))
    st.active = false
    return
  end
  print(string.format("watch_write: WRITE breakpoint on %X (%d bytes)", addr, size or 4))
  print("  now change the lineup in FM, then: stop_write()  and  dump_write()")
end

function stop_write()
  if not st then print("stop_write: not watching") return end
  st.active = false
  pcall(debug_removeBreakpoint, st.addr)
  print(string.format("stop_write: %d write(s) trapped, %d records kept",
    st.total, #st.records))
end

function dump_write()
  if not st then print("dump_write: nothing recorded") return end
  local parts = {}
  for _, r in ipairs(st.records) do
    local rs = {}
    for k, v in pairs(r.regs) do rs[#rs+1] = string.format('"%s":"%s"', k, hx(v)) end
    table.sort(rs)
    local sk = {}
    for _, v in ipairs(r.stack) do sk[#sk+1] = string.format('"%s"', hx(v)) end
    parts[#parts+1] = string.format('{"n":%d,"rip":"%s","regs":{%s},"stack":[%s]}',
      r.n, hx(r.rip), table.concat(rs, ","), table.concat(sk, ","))
  end
  local f = io.open(OUT, "w")
  if not f then print("dump_write: cannot write " .. OUT) return end
  f:write(string.format('{"addr":"%s","total":%d,"records":[%s]}',
    hx(st.addr), st.total, table.concat(parts, ",")))
  f:close()
  print(string.format("dump_write: wrote %s (%d writes, %d records)",
    OUT, st.total, #st.records))
end
