-- Find a club's squad vector -- the std::vector<Player*> {begin, end,
-- capacity_end} header -- in the CURRENT process, starting from whichever
-- player FM has selected.
--
-- Needed after every game restart: the header is a fresh heap allocation each
-- launch, so its address must be re-derived before it can be used or before
-- pointer-scan results can be validated against it.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\locate_vector.lua]])
--   locate_vector()
--
-- METHOD, and why it is this one
--
-- The obvious approach -- scan for pointers to the selected player, walk each
-- hit outward while neighbouring slots look like players, take the longest run
-- -- fails, and failed three times live on 2026-08-15. Two reasons:
--
--   1. The walk BRIDGES between arrays. Adjacent heap allocations frequently
--      hold player pointers too, so a walk starting in Aston Villa's array can
--      run straight into a neighbouring club's. That produced a perfectly valid
--      28-entry vector belonging to Newport County while anchored on a Villa
--      player.
--   2. The authoritative vector is not always the longest run. Arena/UI copies
--      and league-wide lists (a 297-entry block was observed) are longer.
--
-- Fixes, in order of importance:
--   * Walk is CLUB-CONSTRAINED. A slot only extends the run if the player it
--     points at plays for the same club as the anchor. This stops the walk dead
--     at an array boundary instead of bridging, and is what makes the run start
--     trustworthy enough to use as a candidate `begin`.
--   * Corroborate with MULTIPLE squad members, not one anchor. The real squad
--     vector contains the whole squad, so we collect several of the club's
--     players first and require the located vector to contain all the probes.
--     This is the method that actually worked on 2026-08-14 (cluster the hits
--     of several known players), now automated.
--   * The located vector must contain the anchor. Cheap final guard.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local MIN_RUN = 8
local MAX_WALK = 512
local MAX_PROBES = 4         -- squad members to corroborate with (1 scan each)
local BEGIN_CANDIDATES = 4   -- slots from a run start to try as `begin`
local MAX_RUNS = 8

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

-- The critical predicate: a player of the SAME club. Club-constrained walking
-- is what stops runs bridging into a neighbouring club's array.
local function isClubPlayer(p, club)
  return isPlayer(p) and clubName(p) == club
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

-- Walk outward from `slot`, extending only through same-club players, but
-- tolerating short gaps: a squad vector legitimately contains players whose
-- club reads as somewhere else (loanees out) or whose name chain transiently
-- fails to resolve. Stopping at the first mismatch truncates the run -- observed
-- live producing 14- and 17-slot runs for a squad of 23.
local GAP_TOLERANCE = 2

local function walkOne(slot, club, step)
  local edge, gap = slot, 0
  for i = 1, MAX_WALK do
    local a = slot + step * i * 8
    if isClubPlayer(rq(a), club) then
      edge = a
      gap = 0
    else
      gap = gap + 1
      if gap > GAP_TOLERANCE then break end
    end
  end
  return edge
end

local function clubRun(slot, club)
  return walkOne(slot, club, -1), walkOne(slot, club, 1)
end

function locate_vector()
  local anchor = rq(getAddress("pCurrentPlayer"))
  if anchor == nil or anchor == 0 then
    print("locate_vector: no player selected in FM")
    return nil
  end
  local club = clubName(anchor)
  print(string.format("locate_vector: anchor %X (%s, %s)", anchor,
    tostring(lastName(anchor)), tostring(club)))

  -- Step 1: harvest other squad members from the runs around the anchor, so we
  -- can corroborate without needing the user to click through players in FM.
  local anchorHits = scanForQword(anchor)
  print(string.format("locate_vector: %d pointer(s) to the anchor", #anchorHits))

  local members, seenMember = { anchor }, { [anchor] = true }
  for _, h in ipairs(anchorHits) do
    local first, last = clubRun(h, club)
    for a = first, last, 8 do
      local p = rq(a)
      if p and not seenMember[p] then
        seenMember[p] = true
        members[#members + 1] = p
      end
    end
    if #members >= MAX_PROBES * 4 then break end
  end
  print(string.format("locate_vector: harvested %d same-club player record(s)", #members))
  if #members < 2 then
    print("locate_vector: too few squad members found to corroborate")
    return nil
  end

  -- Step 2: probe with several members. The real squad vector holds them all.
  local probes = {}
  for i = 1, math.min(MAX_PROBES, #members) do probes[#probes + 1] = members[i] end
  print(string.format("locate_vector: corroborating with %d probe(s): %s",
    #probes, (function()
      local t = {}
      for _, p in ipairs(probes) do t[#t + 1] = tostring(lastName(p)) end
      return table.concat(t, ", ")
    end)()))

  -- Step 3: collect club-constrained runs around every probe's hits.
  local runs, seenRun = {}, {}
  for _, p in ipairs(probes) do
    for _, h in ipairs(scanForQword(p)) do
      local first, last = clubRun(h, club)
      if not seenRun[first] then
        seenRun[first] = true
        local count = (last - first) / 8 + 1
        if count >= MIN_RUN then
          -- how many of our probes live in this run?
          local hold = 0
          for _, q in ipairs(probes) do
            for s = 0, count - 1 do
              if rq(first + s * 8) == q then hold = hold + 1 break end
            end
          end
          runs[#runs + 1] = { addr = first, count = count, holds = hold }
        end
      end
    end
  end

  -- Best = holds the most probes, tie-break on shorter (arena lists are longer).
  table.sort(runs, function(a, b)
    if a.holds ~= b.holds then return a.holds > b.holds end
    return a.count < b.count
  end)
  print(string.format("locate_vector: %d candidate run(s)", #runs))
  for i = 1, math.min(#runs, MAX_RUNS) do
    print(string.format("   run %d: %X, %d players, holds %d/%d probes",
      i, runs[i].addr, runs[i].count, runs[i].holds, #probes))
  end

  -- Step 4: header lookup, requiring the vector to contain the anchor.
  --
  -- Probe BOTH directions from the run start. A run truncated at its front
  -- (the walk stopped on a loanee or an unresolvable slot) has its real `begin`
  -- *behind* the run start, so forward-only probing can never find the header.
  -- Ordered by likelihood: exact start first, then alternating outward.
  local offsets = { 0, -1, 1, -2, 2, -3, 3, -4, -5, -6 }
  for _, k in ipairs(offsets) do
    for i = 1, math.min(#runs, MAX_RUNS) do
      local begin = runs[i].addr + k * 8
      local hdr, count = headerFor(begin)
      if hdr then
        local holdsAnchor = false
        for s = 0, count - 1 do
          if rq(begin + s * 8) == anchor then holdsAnchor = true break end
        end
        if holdsAnchor then
          print(string.format(
            "locate_vector: HEADER %X -> begin %X, %d players (run %X, offset %d)",
            hdr, begin, count, runs[i].addr, k))
          print(string.format("locate_vector: use  dump_squad_to_file(nil, \"%X\")", hdr))
          return { header = hdr, begin = begin, count = count }
        else
          print(string.format("locate_vector: rejected header %X (%d players) -- lacks the anchor",
            hdr, count))
        end
      end
    end
  end

  print("locate_vector: no vector header found across any candidate run")
  return nil
end
