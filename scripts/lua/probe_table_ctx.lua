-- Work out what the registers captured at the club-name read actually point at.
--
-- CONTEXT: watch_club_access.lua trapped a single instruction (fm.exe+1440BCF1D)
-- that reads club+0xB8 while the league table renders. Two registers held the
-- SAME value on every hit while the stack registers varied -- R13 and R10. Those
-- are the loop's context rather than per-call scratch, so they are the candidates
-- for the table / competition object we have never located.
--
-- THE DECISIVE TEST: the league table must reference all 20 Premier League clubs.
-- So walk each candidate region, resolve every qword as a possible club object,
-- and see whether a run of them names real clubs. Five previous approaches failed
-- because they assumed where the link lived; this asks the game to show us.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_table_ctx.lua]])
--   probe_table_ctx()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\table_ctx.json]]
local LOG  = REPO .. [[\data\snapshots\table_ctx.log]]

-- CE's Lua Engine output pane only keeps a few visible lines and is painful to
-- scroll through over a remote screenshot, so everything printed here is also
-- appended to LOG for offline reading.
local logf = nil
local realprint = print
local function print(...)
  realprint(...)
  if logf then
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts+1] = tostring((select(i, ...))) end
    logf:write(table.concat(parts, "\t") .. "\n")
    logf:flush()
  end
end

local NAME_PTR_OFF = 0xB8
local NAME_STR_OFF = 0x4

-- Constant registers from data/snapshots/club_access.json, plus the varying
-- ones kept for completeness so nothing is dismissed without being looked at.
local CANDIDATES = {
  { name = "R13", addr = 0x5C9A570 },
  { name = "R10", addr = 0x43260B0 },
  { name = "R14/RSI_a", addr = 0xDEADB680 },
  { name = "R14/RSI_b", addr = 0xDEADB560 },
}

local RIP = 0x1440BCF1D
local SPAN = 0x400          -- bytes either side to sweep for club pointers

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

-- A club object is recognised the same way dump_club_record.lua does it:
-- club+0xB8 -> name object, +0x4 -> printable name.
local function clubName(p)
  if not p or p < 0x10000 then return nil end
  local q = rq(p + NAME_PTR_OFF)
  if not q or q < 0x10000 then return nil end
  local s = readStr(q + NAME_STR_OFF)
  if not s then return nil end
  -- guard against random bytes that happen to be printable
  if #s < 3 or #s > 48 then return nil end
  if s:match("^[%w%s%.%-'&/%(%)]+$") then return s end
  return nil
end

local function jesc(s) return tostring(s):gsub('\\','\\\\'):gsub('"','\\"') end

local results = {}

local function sweep(label, base)
  print(string.format("\n=== %s @ %X ===", label, base))
  if not rq(base) then
    print("  unreadable")
    return
  end

  -- 1. Direct qword window, resolving each slot as a club.
  local hits = {}
  local lo = base - SPAN
  for off = -SPAN, SPAN, 8 do
    local a = base + off
    local v = rq(a)
    if v then
      local n = clubName(v)
      if n then
        hits[#hits+1] = { off = off, addr = a, ptr = v, name = n }
      end
    end
  end

  if #hits > 0 then
    print(string.format("  %d club pointers in +/-%X:", #hits, SPAN))
    for _, h in ipairs(hits) do
      print(string.format("    %+6d  %X -> %X  %s", h.off, h.addr, h.ptr, h.name))
    end
  else
    print(string.format("  no club pointers within +/-%X", SPAN))
  end

  -- 2. Treat the slot as a std::vector header {begin,end,cap} and walk it.
  local b, e, c = rq(base), rq(base+8), rq(base+16)
  if b and e and c and e >= b and c >= e and b > 0x10000 then
    local n = (e - b) / 8
    if n > 0 and n <= 4096 then
      print(string.format("  looks like a vector header: begin=%X end=%X cap=%X n=%d",
        b, e, c, n))
      local named = 0
      for i = 0, math.min(n, 64) - 1 do
        local v = rq(b + i*8)
        local nm = v and clubName(v) or nil
        if nm then
          named = named + 1
          print(string.format("    [%2d] %X  %s", i, v, nm))
        end
      end
      print(string.format("    -> %d/%d slots resolve as clubs", named, math.min(n,64)))
    end
  end

  -- 3. Follow one level of indirection: each qword in a small window might be a
  --    pointer to the actual container.
  for off = 0, 0x80, 8 do
    local v = rq(base + off)
    if v and v > 0x10000 then
      local bb, ee = rq(v), rq(v+8)
      if bb and ee and ee > bb and (ee-bb) % 8 == 0 then
        local n = (ee-bb)/8
        if n >= 4 and n <= 256 then
          local named, first = 0, nil
          for i = 0, math.min(n,40)-1 do
            local pv = rq(bb + i*8)
            local nm = pv and clubName(pv) or nil
            if nm then named = named + 1; first = first or nm end
          end
          if named >= 4 then
            print(string.format("  [+%X] -> %X : vector of %d, %d resolve as clubs (first '%s')",
              off, v, n, named, tostring(first)))
            results[#results+1] = string.format(
              '{"via":"%s+%X","container":"%X","n":%d,"clubs":%d}',
              jesc(label), off, v, n, named)
          end
        end
      end
    end
  end
end

function probe_table_ctx()
  logf = io.open(LOG, "w")
  results = {}
  print("probe_table_ctx: interpreting the trapped register context")

  local ok, dis = pcall(disassemble, RIP)
  if ok and dis then print("instruction at RIP: " .. tostring(dis)) end
  for d = -0x30, 0x10, 0x8 do
    local ok2, dd = pcall(disassemble, RIP + d)
    if ok2 and dd then print(string.format("  %X  %s", RIP + d, tostring(dd))) end
  end

  for _, c in ipairs(CANDIDATES) do
    sweep(c.name, c.addr)
  end

  local f = io.open(OUT, "w")
  if f then
    f:write("{\"containers\":[" .. table.concat(results, ",") .. "]}")
    f:close()
    print("\nprobe_table_ctx: wrote " .. OUT)
  end
  if logf then logf:close(); logf = nil end
  realprint("probe_table_ctx: full output in " .. LOG)
end
