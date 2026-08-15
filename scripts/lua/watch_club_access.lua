-- Break on reads of a club object's name-pointer field and record who did it.
--
-- WHY THIS EXISTS
-- Five blind-scanning approaches to the league table have failed (see
-- docs/phase1-notes.md). This is the escalation those notes point at: use the
-- debugger instead of guessing at structure. The reasoning is that the league
-- table screen cannot draw a row without dereferencing that club's name, so a
-- hardware access breakpoint on club+0xB8 must trap the render code. Whatever
-- register then holds the iterating structure is the table (or the competition
-- object, which we have never located).
--
-- CHOICE OF ANCHOR: use a club that is NOT otherwise on screen. club+0xB8 is
-- read by anything that draws that club's name, so anchoring on our own club
-- buries the signal. Sitting on an Aston Villa screen and anchoring on Everton
-- means essentially the only thing that reads it is the league table.
--
-- SAFETY: the callback does no file I/O and no allocation-heavy work -- it runs
-- on the debugger thread and the game is stopped for its duration. Everything is
-- buffered and written out later by dump_club_access(). Hits are capped so a hot
-- address cannot livelock the game.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\watch_club_access.lua]])
--   watch_club_access()          -- default anchor: Everton name-ptr field
--   -- ... navigate FM to the league table ...
--   mark_club_access("opened league table")
--   stop_club_access()
--   dump_club_access()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT = REPO .. [[\data\snapshots\club_access.json]]

local NAME_PTR_OFF = 0xB8

-- Recorded 3 Oct 2020 in-game, re-verified live by probe_club_anchor.lua.
CLUB_ADDR = {
  Leicester   = 0x975B0478,
  AstonVilla  = 0x975AA370,
  ManCity     = 0x975B0CE8,
  Everton     = 0x975AE420,
}

local MAX_HITS   = 250   -- hard cap; the game is frozen during each callback
local STACK_SLOTS = 6    -- return address + a little call context

local state = nil

local function hx(v)
  if not v then return nil end
  return string.format("%X", v)
end

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

-- Called by CE on every breakpoint hit. Must not error and must return 1,
-- otherwise the debugger stops and takes the game with it.
function debugger_onBreakpoint()
  if not state or not state.active then return 1 end

  pcall(function()
    state.hits = state.hits + 1

    if state.hits > MAX_HITS then
      state.active = false
      pcall(debug_removeBreakpoint, state.anchor)
      return
    end

    local rip = RIP
    state.byRip[rip] = (state.byRip[rip] or 0) + 1

    -- Only keep a full register snapshot the first few times we see a given
    -- instruction. Repeats of the same RIP tell us nothing new and the list
    -- would otherwise be dominated by one hot loop.
    if state.byRip[rip] <= 3 then
      local stack = {}
      for i = 0, STACK_SLOTS - 1 do
        stack[#stack + 1] = rq(RSP + i * 8)
      end
      state.records[#state.records + 1] = {
        n = state.hits, phase = state.phase, rip = rip,
        regs = {
          RAX = RAX, RBX = RBX, RCX = RCX, RDX = RDX,
          RSI = RSI, RDI = RDI, RBP = RBP, RSP = RSP,
          R8 = R8, R9 = R9, R10 = R10, R11 = R11,
          R12 = R12, R13 = R13, R14 = R14, R15 = R15,
        },
        stack = stack,
      }
    end
  end)

  return 1
end

function watch_club_access(clubName, offset)
  clubName = clubName or "Everton"
  local base = CLUB_ADDR[clubName]
  if not base then
    print("watch_club_access: unknown club '" .. tostring(clubName) .. "'")
    return
  end
  local anchor = base + (offset or NAME_PTR_OFF)

  state = {
    active = true, hits = 0, records = {}, byRip = {},
    anchor = anchor, club = clubName, base = base,
    phase = "baseline",
  }

  local ok, err = pcall(debug_setBreakpoint, anchor, 8, bptAccess)
  if not ok then
    print("watch_club_access: FAILED to set breakpoint: " .. tostring(err))
    print("  If the Windows debugger is blocked, try the VEH debugger:")
    print("  Settings -> Debugger Options -> Debugger interface -> VEH Debugger")
    state.active = false
    return
  end

  print(string.format("watch_club_access: breakpoint on %s+%X = %X (%s)",
    clubName, offset or NAME_PTR_OFF, anchor, "bptAccess, 8 bytes"))
  print("  phase is 'baseline'. Now go to the league table in FM, then run:")
  print("    mark_club_access(\"opened league table\")")
  print("  and when done:  stop_club_access()  then  dump_club_access()")
end

-- Label everything from here on, so hits caused by the table screen can be told
-- apart from whatever was already touching the club.
function mark_club_access(label)
  if not state then print("mark_club_access: not watching") return end
  state.phase = label or "marked"
  print(string.format("mark_club_access: phase -> '%s' (%d hits so far)",
    state.phase, state.hits))
end

function stop_club_access()
  if not state then print("stop_club_access: not watching") return end
  state.active = false
  pcall(debug_removeBreakpoint, state.anchor)
  print(string.format("stop_club_access: removed breakpoint, %d hits, %d distinct RIPs",
    state.hits, (function()
      local n = 0
      for _ in pairs(state.byRip) do n = n + 1 end
      return n
    end)()))
end

function dump_club_access()
  if not state then print("dump_club_access: nothing recorded") return end

  local parts = {}
  for _, r in ipairs(state.records) do
    local rs = {}
    for k, v in pairs(r.regs) do
      rs[#rs + 1] = string.format('"%s":"%s"', k, hx(v) or "0")
    end
    table.sort(rs)
    local st = {}
    for _, v in ipairs(r.stack) do
      st[#st + 1] = string.format('"%s"', hx(v) or "0")
    end
    parts[#parts + 1] = string.format(
      '{"n":%d,"phase":"%s","rip":"%s","regs":{%s},"stack":[%s]}',
      r.n, tostring(r.phase), hx(r.rip), table.concat(rs, ","), table.concat(st, ","))
  end

  local rips = {}
  for rip, n in pairs(state.byRip) do
    rips[#rips + 1] = string.format('{"rip":"%s","count":%d}', hx(rip), n)
  end

  local json = string.format(
    '{"club":"%s","base":"%s","anchor":"%s","hits":%d,"rips":[%s],"records":[%s]}',
    state.club, hx(state.base), hx(state.anchor), state.hits,
    table.concat(rips, ","), table.concat(parts, ","))

  local f = io.open(OUT, "w")
  if not f then print("dump_club_access: cannot write " .. OUT) return end
  f:write(json)
  f:close()
  print(string.format("dump_club_access: wrote %s (%d hits, %d records)",
    OUT, state.hits, #state.records))
end
