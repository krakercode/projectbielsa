-- Break on the instruction that handles a club's name during rendering, and
-- record which club it is called for, in order.
--
-- WHY THIS AND NOT watch_club_access.lua
-- That script anchored on ONE club's memory (Everton+0xB8), so it only ever saw
-- Everton's calls. Two registers looked "constant" across hits, but with a single
-- club there was nothing for them to vary against -- they may simply be Everton's
-- context. Breaking on the *instruction* instead means every club that renders
-- passes through, which answers the real question:
--
--   Does this function get called once per club, in league-table order?
--
-- If yes, this is the table render loop, the call order IS the standings order,
-- and whatever register or stack slot walks between calls is the container the
-- table lives in -- the thing five scanning approaches failed to find.
--
-- ADDRESS: fm.exe+1440BCF1D, captured by watch_club_access.lua. At this point
-- RBX still holds the club pointer and RAX holds its name pointer.
--
-- SAFETY: this may be a generic string helper called for far more than clubs, so
-- the callback rejects non-club hits after a single qword read, caps recorded
-- entries, and hard-removes itself after a total-hit ceiling so a hot instruction
-- cannot livelock the game.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\watch_table_render.lua]])
--   watch_table_render()
--   -- ... navigate FM to the league table ...
--   stop_table_render()
--   dump_table_render()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\table_render.json]]
local LOG  = REPO .. [[\data\snapshots\table_render.log]]

local BP_ADDR = 0x1440BCF1D

local NAME_PTR_OFF = 0xB8
local NAME_STR_OFF = 0x4

local MAX_RECORDS = 220     -- club-resolving hits to keep
local MAX_TOTAL   = 20000   -- absolute ceiling on callback invocations
-- Stack grows down, so RSP+N walks UP into the caller frames. 48 qwords was not
-- enough: every slot in that window was either constant or a copy of the club
-- pointer. The loop counter lives in the caller's locals, further up.
local STACK_DEPTH = 160     -- qwords from RSP (RSP .. RSP+0x4F8)

-- The 20 Premier League club objects, captured from the alphabetical render run.
-- Filtering on exact addresses keeps out the false positives the loose name check
-- produced ("number", "time", "hashtag" -- UI descriptor objects that happen to
-- carry a string at the same offset as a club name).
PL_ADDR = {
  [0x975AA208]="Arsenal", [0x975AA370]="Aston Villa", [0x975AB888]="Brighton",
  [0x975ABE28]="Burnley", [0x975AC968]="Chelsea", [0x975ADA48]="Crystal Palace",
  [0x975AE420]="Everton", [0x975AE9C0]="Fulham", [0x975B01A8]="Leeds",
  [0x975B0478]="Leicester", [0x975B08B0]="Liverpool", [0x975B0CE8]="Man City",
  [0x975B0E50]="Man Utd", [0x975B1990]="Newcastle", [0x975B35B0]="Sheff Utd",
  [0x975B3CB8]="Southampton", [0x975B51D0]="Tottenham", [0x975B58D8]="West Brom",
  [0x975B5A40]="West Ham", [0x975B6148]="Wolves",
}

local st = nil

local function hx(v) if not v then return nil end return string.format("%X", v) end

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function clubNameFast(p)
  if not p or p < 0x100000 then return nil end
  local q = rq(p + NAME_PTR_OFF)
  if not q or q < 0x100000 then return nil end        -- fast reject
  local ok, s = pcall(readString, q + NAME_STR_OFF, 48, false)
  if not ok or not s or #s < 3 or #s > 48 then return nil end
  if s:match("^[%w%s%.%-'&/%(%)]+$") then return s end
  return nil
end

function debugger_onBreakpoint()
  if not st or not st.active then return 1 end

  pcall(function()
    st.total = st.total + 1
    if st.total > MAX_TOTAL then
      st.active = false
      pcall(debug_removeBreakpoint, BP_ADDR)
      return
    end

    local club = PL_ADDR[RBX]
    if not club then
      st.nonclub = st.nonclub + 1
      return
    end

    st.clubHits = st.clubHits + 1
    if #st.records < MAX_RECORDS then
      local stack = {}
      for i = 0, STACK_DEPTH - 1 do stack[#stack+1] = rq(RSP + i*8) end
      st.records[#st.records+1] = {
        seq = st.clubHits, phase = st.phase, club = club, rbx = RBX,
        regs = { RAX=RAX, RCX=RCX, RDX=RDX, RSI=RSI, RDI=RDI, RBP=RBP, RSP=RSP,
                 R8=R8, R9=R9, R10=R10, R11=R11, R12=R12, R13=R13,
                 R14=R14, R15=R15 },
        stack = stack,
      }
    end
  end)

  return 1
end

function watch_table_render(phase)
  st = { active = true, total = 0, clubHits = 0, nonclub = 0,
         records = {}, phase = phase or "arming" }

  local ok, err = pcall(debug_setBreakpoint, BP_ADDR, 1, bptExecute)
  if not ok then
    print("watch_table_render: FAILED to set breakpoint: " .. tostring(err))
    st.active = false
    return
  end
  print(string.format("watch_table_render: execute breakpoint at %X", BP_ADDR))
  print("  navigate FM to the league table, then: stop_table_render()")
end

function mark_table_render(label)
  if not st then print("mark_table_render: not watching") return end
  st.phase = label or "marked"
  print(string.format("mark_table_render: phase -> '%s' (%d club hits / %d total)",
    st.phase, st.clubHits, st.total))
end

function stop_table_render()
  if not st then print("stop_table_render: not watching") return end
  st.active = false
  pcall(debug_removeBreakpoint, BP_ADDR)
  print(string.format("stop_table_render: %d total hits, %d resolved as clubs, %d not",
    st.total, st.clubHits, st.nonclub))
end

function dump_table_render()
  if not st then print("dump_table_render: nothing recorded") return end

  local logf = io.open(LOG, "w")
  local function say(s)
    print(s)
    if logf then logf:write(s .. "\n") end
  end

  say(string.format("total=%d clubHits=%d nonclub=%d records=%d",
    st.total, st.clubHits, st.nonclub, #st.records))
  say("call order (this is the question -- is it league-table order?):")
  for _, r in ipairs(st.records) do
    say(string.format("  %3d  %-28s RBX=%s R13=%s R10=%s R12=%s R15=%s",
      r.seq, r.club, hx(r.rbx), hx(r.regs.R13), hx(r.regs.R10),
      hx(r.regs.R12), hx(r.regs.R15)))
  end

  local parts = {}
  for _, r in ipairs(st.records) do
    local rs = {}
    for k, v in pairs(r.regs) do rs[#rs+1] = string.format('"%s":"%s"', k, hx(v) or "0") end
    table.sort(rs)
    local sk = {}
    for _, v in ipairs(r.stack) do sk[#sk+1] = string.format('"%s"', hx(v) or "0") end
    parts[#parts+1] = string.format(
      '{"seq":%d,"phase":"%s","club":"%s","rbx":"%s","regs":{%s},"stack":[%s]}',
      r.seq, tostring(r.phase), tostring(r.club):gsub('"','\\"'), hx(r.rbx),
      table.concat(rs, ","), table.concat(sk, ","))
  end
  local f = io.open(OUT, "w")
  if f then
    f:write(string.format('{"total":%d,"clubHits":%d,"nonclub":%d,"records":[%s]}',
      st.total, st.clubHits, st.nonclub, table.concat(parts, ",")))
    f:close()
    say("dump_table_render: wrote " .. OUT)
  end
  if logf then logf:close() end
end
