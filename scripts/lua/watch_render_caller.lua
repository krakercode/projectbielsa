-- Break INSIDE the loop that walks the competition's 20 clubs.
--
-- THE POINT
-- watch_table_render.lua broke on the callee (fm.exe+1440BCF1D), which fires once
-- per club during a league-table render. From inside the callee the loop's own
-- state was invisible: every register was either the club, its name pointer, or
-- constant. The captured return chain was 1440DB515 -> 1440BE24A -> 1455A87E3.
--
-- 1440DB515 is the return address *inside the caller*, i.e. inside the loop
-- itself. Breaking there means the iterator and the collection base are live in
-- registers at the moment of the break. Whichever register advances by a constant
-- stride between consecutive hits IS the walk over the competition's club
-- collection -- the object docs/phase1-notes.md calls the biggest gap.
--
-- No club filter here: unlike the callee this is a specific call site, so it
-- should not be hot. Everything is captured and correlated offline by matching
-- registers against the known club / BBD9 record addresses.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\watch_render_caller.lua]])
--   watch_render_caller()          -- default 1440DB515
--   -- ... navigate FM to the league table ...
--   stop_render_caller()
--   dump_render_caller()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\render_caller.json]]

local DEFAULT_BP  = 0x1440DB515
local MAX_RECORDS = 600
local MAX_TOTAL   = 20000
-- 32 was too shallow at 1455A87E3: across the 20-club table-order run every
-- register bar RBX was identical and no stack slot moved. The iterator lives
-- further up the caller frames, so reach as deep as the callee capture did.
local STACK_DEPTH = 160

-- RESULT 2026-08-16: 1440DB515 is a GENERIC name-formatting helper, not the loop
-- -- 12,582 hits during one navigation and only 2 of 600 captured records touched
-- a known club. Capturing the first N hits therefore fills up with unrelated UI
-- work before the table even renders. Climbing to the next frame (1455A87E3)
-- needs a capture-time filter, below, so noise cannot consume the cap.
local FILTER = false     -- when true, only record hits that see a known club

-- Club objects and BBD9 per-club competition records, keyed for O(1) lookup.
KNOWN = {
  [0x975AA208]="Arsenal",[0x975AA370]="Aston Villa",[0x975AB888]="Brighton",
  [0x975ABE28]="Burnley",[0x975AC968]="Chelsea",[0x975ADA48]="Crystal Palace",
  [0x975AE420]="Everton",[0x975AE9C0]="Fulham",[0x975B01A8]="Leeds",
  [0x975B0478]="Leicester",[0x975B08B0]="Liverpool",[0x975B0CE8]="Man City",
  [0x975B0E50]="Man Utd",[0x975B1990]="Newcastle",[0x975B35B0]="Sheff Utd",
  [0x975B3CB8]="Southampton",[0x975B51D0]="Tottenham",[0x975B58D8]="West Brom",
  [0x975B5A40]="West Ham",[0x975B6148]="Wolves",
  [0xBBD953F8]="Arsenal",[0xBBD954B0]="Aston Villa",[0xBBD95F78]="Brighton",
  [0xBBD96258]="Burnley",[0xBBD96818]="Chelsea",[0xBBD970B8]="Crystal Palace",
  [0xBBD975C0]="Everton",[0xBBD978A0]="Fulham",[0xBBD984D8]="Leeds",
  [0xBBD98648]="Leicester",[0xBBD98870]="Liverpool",[0xBBD98A98]="Man City",
  [0xBBD98B50]="Man Utd",[0xBBD99110]="Newcastle",[0xBBD99F70]="Sheff Utd",
  [0xBBD9A308]="Southampton",[0xBBD9ADD0]="Tottenham",[0xBBD9B168]="West Brom",
  [0xBBD9B220]="West Ham",[0xBBD9B5B8]="Wolves",
}

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
      pcall(debug_removeBreakpoint, st.bp)
      return
    end
    if #st.records >= MAX_RECORDS then return end

    local stack = {}
    for i = 0, STACK_DEPTH - 1 do stack[#stack+1] = rq(RSP + i*8) end

    if st.filter then
      -- cheap registers first, then the stack window
      local seen = KNOWN[RBX] or KNOWN[RAX] or KNOWN[RCX] or KNOWN[RDX]
                or KNOWN[RSI] or KNOWN[RDI] or KNOWN[R12] or KNOWN[R13]
                or KNOWN[R14] or KNOWN[R15]
      if not seen then
        for i = 1, #stack do
          if stack[i] and KNOWN[stack[i]] then seen = KNOWN[stack[i]]; break end
        end
      end
      if not seen then st.skipped = st.skipped + 1 return end
      st.matched = st.matched + 1
    end

    st.records[#st.records+1] = {
      n = st.total,
      regs = { RAX=RAX, RBX=RBX, RCX=RCX, RDX=RDX, RSI=RSI, RDI=RDI,
               RBP=RBP, RSP=RSP, R8=R8, R9=R9, R10=R10, R11=R11,
               R12=R12, R13=R13, R14=R14, R15=R15 },
      stack = stack,
    }
  end)
  return 1
end

function watch_render_caller(addr, filter)
  local bp = addr or DEFAULT_BP
  st = { active = true, total = 0, records = {}, bp = bp,
         filter = (filter == nil) and FILTER or filter,
         skipped = 0, matched = 0 }
  local ok, err = pcall(debug_setBreakpoint, bp, 1, bptExecute)
  if not ok then
    print("watch_render_caller: FAILED to set breakpoint: " .. tostring(err))
    st.active = false
    return
  end
  print(string.format("watch_render_caller: execute breakpoint at %X", bp))
  print("  navigate FM to the league table, then: stop_render_caller()")
end

function stop_render_caller()
  if not st then print("stop_render_caller: not watching") return end
  st.active = false
  pcall(debug_removeBreakpoint, st.bp)
  print(string.format("stop_render_caller: %d hits, %d records kept (filter=%s, matched=%d skipped=%d)",
    st.total, #st.records, tostring(st.filter), st.matched, st.skipped))
end

function dump_render_caller()
  if not st then print("dump_render_caller: nothing recorded") return end
  local parts = {}
  for _, r in ipairs(st.records) do
    local rs = {}
    for k, v in pairs(r.regs) do rs[#rs+1] = string.format('"%s":"%s"', k, hx(v)) end
    table.sort(rs)
    local sk = {}
    for _, v in ipairs(r.stack) do sk[#sk+1] = string.format('"%s"', hx(v)) end
    parts[#parts+1] = string.format('{"n":%d,"regs":{%s},"stack":[%s]}',
      r.n, table.concat(rs, ","), table.concat(sk, ","))
  end
  local f = io.open(OUT, "w")
  if not f then print("dump_render_caller: cannot write " .. OUT) return end
  f:write(string.format('{"bp":"%s","total":%d,"records":[%s]}',
    hx(st.bp), st.total, table.concat(parts, ",")))
  f:close()
  print(string.format("dump_render_caller: wrote %s (%d hits, %d records)",
    OUT, st.total, #st.records))
end
