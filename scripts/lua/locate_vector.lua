-- Find the squad vector's {begin, end, capacity_end} header address in the
-- CURRENT process, starting from whichever player FM has selected.
--
-- This is the step you need after every game restart: the header is a fresh
-- heap allocation each launch, so its address has to be re-derived before it
-- can be used (or before pointer-scan results can be validated against it).
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\locate_vector.lua]])
--   locate_vector()
--
-- Method: scan for pointers to the selected player, expand each hit into a run
-- of contiguous player pointers, then look for a std::vector header pointing at
-- one of them.
--
-- Two things this has to work around, both learned the hard way:
--   * runAround over-extends past the real bounds whenever neighbouring heap
--     allocations happen to hold player pointers, so the run start is often not
--     the vector's `begin`. We try the first few slots of each run as candidate
--     begins rather than trusting the start.
--   * The authoritative vector is not always the LONGEST run -- arena copies
--     can be longer. So probe every candidate run, not just the best one.
--
-- Cost is one memory scan per (run, begin) probe, so it runs cheap probes
-- across all runs first before spending scans on deeper offsets.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local MIN_RUN = 8
local MAX_WALK = 256
local MAX_RUNS = 8           -- distinct runs to consider
local BEGIN_CANDIDATES = 4   -- slots from each run start to try as `begin`

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

local function printable(s)
  if not s or #s == 0 then return false end
  for i = 1, #s do
    local b = s:byte(i)
    if b < 32 or b > 126 then return false end
  end
  return true
end

local function lastName(p) return readStr(FM_resolveFrom(p, { 0x2D0, 0x0, 0x4 })) end
local function clubName(p) return readStr(FM_resolveFrom(p, { 0x88, 0x30, 0xB8, 0x4 })) end

local function isPlayer(p)
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return false end
  local vt = rq(p)
  if vt == nil or vt == 0 then return false end
  if not printable(lastName(p)) then return false end
  local okca, ca = pcall(readSmallInteger, p + 0x1FC)
  return okca and ca ~= nil and ca >= 1 and ca <= 200
end

local function scanForQword(value)
  local ms = createMemScan()
  ms.firstScan(soExactValue, vtQword, rtRounded, string.format("%X", value), nil,
    0, 0x7fffffffffff, "*X*C*W", fsmAligned, "8", true, false, false, false)
  ms.waitTillDone()
  local fl = createFoundList(ms)
  fl.initialize()
  local out = {}
  for i = 0, fl.Count - 1 do out[#out + 1] = tonumber(fl.Address[i], 16) end
  fl.destroy()
  ms.destroy()
  return out
end

local function headerFor(begin)
  for _, r in ipairs(scanForQword(begin)) do
    local e, cap = rq(r + 8), rq(r + 16)
    if e and cap and e > begin and cap >= e and (e - begin) % 8 == 0 then
      local count = (e - begin) / 8
      if count >= MIN_RUN and count <= 1024 then return r, count end
    end
  end
  return nil
end

function locate_vector()
  local anchor = rq(getAddress("pCurrentPlayer"))
  if anchor == nil or anchor == 0 then
    print("locate_vector: no player selected in FM")
    return nil
  end
  local wantClub = clubName(anchor)
  print(string.format("locate_vector: anchor %X (%s, %s)", anchor,
    tostring(lastName(anchor)), tostring(wantClub)))

  local hits = scanForQword(anchor)
  print(string.format("locate_vector: %d pointer(s) to the anchor", #hits))

  -- Collect distinct runs.
  local runs, seen = {}, {}
  for _, h in ipairs(hits) do
    local first, last = h, h
    for i = 1, MAX_WALK do
      if isPlayer(rq(h - i * 8)) then first = h - i * 8 else break end
    end
    for i = 1, MAX_WALK do
      if isPlayer(rq(h + i * 8)) then last = h + i * 8 else break end
    end
    if not seen[first] then
      seen[first] = true
      local count = (last - first) / 8 + 1
      if count >= MIN_RUN then runs[#runs + 1] = { addr = first, count = count } end
    end
  end
  table.sort(runs, function(a, b) return a.count > b.count end)
  print(string.format("locate_vector: %d candidate run(s)", #runs))
  for i = 1, math.min(#runs, MAX_RUNS) do
    print(string.format("   run %d: %X, %d players", i, runs[i].addr, runs[i].count))
  end

  -- Pass 1: cheapest probe -- run start as `begin`, across every run.
  -- Pass 2+: walk further into each run, for the over-extension case.
  for k = 0, BEGIN_CANDIDATES - 1 do
    for i = 1, math.min(#runs, MAX_RUNS) do
      local begin = runs[i].addr + k * 8
      local hdr, count = headerFor(begin)
      if hdr then
        -- The vector must actually CONTAIN the anchor. Without this check the
        -- walk can bridge out of the anchor's array into a neighbouring club's
        -- array on the heap and return that club's (perfectly valid) header --
        -- observed live returning Newport County's squad while anchored on an
        -- Aston Villa player.
        local holdsAnchor = false
        for s = 0, count - 1 do
          if rq(begin + s * 8) == anchor then holdsAnchor = true break end
        end
        if holdsAnchor then
          print(string.format(
            "locate_vector: HEADER %X -> begin %X, %d players (run %X, offset %d slot(s))",
            hdr, begin, count, runs[i].addr, k))
          print(string.format("locate_vector: use  dump_squad_to_file(nil, \"%X\")", hdr))
          return { header = hdr, begin = begin, count = count }
        else
          print(string.format(
            "locate_vector: rejected header %X (%d players) -- does not contain the anchor",
            hdr, count))
        end
      end
    end
  end

  print("locate_vector: no vector header found across any candidate run")
  print("locate_vector: try browsing the Squad screen in FM first -- the vector")
  print("               may not be materialised until the squad list is viewed")
  return nil
end
