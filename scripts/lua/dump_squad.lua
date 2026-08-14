-- Phase 1: dump the whole squad, not just the selected player.
--
-- HOW IT FINDS THE SQUAD
-- FM keeps a club's senior squad as a std::vector<Player*>. On the save this
-- was developed against the vector header sat at 0x6B7CC8C0 --
-- {begin, end, capacity_end} -- with begin pointing at a packed array of 23
-- player pointers. That header is embedded by value inside its owning object
-- (nothing points *at* it), so there's no pointer path to it yet and its
-- address is a fresh heap allocation every time the game starts.
--
-- Rather than hardcode an address that dies on restart, this locates the array
-- from the live selection each time:
--   1. take the currently-selected player (pCurrentPlayer)
--   2. scan memory for qwords equal to that record's address -- every place
--      holding a pointer to them
--   3. around each hit, walk outwards while neighbouring slots also resolve as
--      player records, giving a contiguous run
--   4. keep runs that look like a squad: long enough, and every member plays
--      for the same club as the selected player
--   5. dump every player in the best run using dump_state.lua's field tables
--
-- That costs a memory scan per call (a few seconds), which is fine for
-- between-match decisions and survives restarts, patches and heap movement.
--
-- VERIFIED LIVE 2026-08-14 (Aston Villa, 27 Jul 2020): returns 20 Villa
-- players with correct CA/PA/attributes and correct first+last names for
-- every one of them.
--
-- KNOWN LIMITATION -- it found 20, and the club's actual senior squad is 23.
-- FM keeps several arrays holding the same player pointers: the authoritative
-- std::vector plus what look like UI/list arena copies (the same region also
-- holds unrelated lists, e.g. a national squad). This picks the longest
-- same-club contiguous run, which landed on an arena copy whose neighbouring
-- slots had since been overwritten, truncating the run. The fix is to prefer a
-- run that is backed by a real vector header -- scan for a qword equal to the
-- run's start address and require the following qword to equal its end -- and
-- only fall back to the longest run when no header is found. Deliberately not
-- implemented blind: it needs a live session to verify, which is exactly the
-- mistake that produced the offset-order bug.
--
-- Note on names: "Full Name" (the 0x2B8 chain) is a lazily-populated cache and
-- comes back nil for players FM hasn't rendered a full name for yet. First and
-- Last name resolve reliably for everyone -- prefer those.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_squad.lua]])
--   dump_squad_to_file()
--
-- Requires the base table's "-----[==Features==]-----" and "Current Player"
-- scripts active, and a player from the squad selected in FM.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local DEFAULT_OUT = REPO .. [[\data\snapshots\squad.json]]

dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local MIN_SQUAD = 8         -- shorter runs than this aren't a squad
local MAX_WALK = 256        -- don't walk further than this in either direction
local MAX_HEADER_SCANS = 8  -- vector-header lookups cost a memory scan each

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

-- Expand around `slot` while neighbouring slots also hold player records.
local function runAround(slot)
  local first, last = slot, slot
  for i = 1, MAX_WALK do
    if isPlayer(rq(slot - i * 8)) then first = slot - i * 8 else break end
  end
  for i = 1, MAX_WALK do
    if isPlayer(rq(slot + i * 8)) then last = slot + i * 8 else break end
  end
  return first, last
end

-- Is `start` the begin pointer of a real std::vector? Looks for a
-- {begin, end, capacity_end} header pointing at it and returns the element
-- count from the header, which is authoritative -- unlike a walked run, it
-- can't be truncated by a stale neighbouring slot.
local function vectorCountFor(start)
  local refs = scanForQword(start)
  for _, r in ipairs(refs) do
    local e, cap = rq(r + 8), rq(r + 16)
    if e and cap and e > start and cap >= e and (e - start) % 8 == 0 then
      local count = (e - start) / 8
      if count >= MIN_SQUAD and count <= 1024 then
        print(string.format("dump_squad: vector header at %X -> %d players", r, count))
        return count
      end
    end
  end
  return nil
end

-- Returns {addr, count, source} for the best squad-looking array, or nil.
-- Prefers an array backed by a real vector header; falls back to the longest
-- same-club run of player pointers.
function find_squad_array()
  local base = rq(getAddress("pCurrentPlayer"))
  if base == nil or base == 0 then
    print("dump_squad: no player selected")
    return nil
  end
  local wantClub = clubName(base)
  print(string.format("dump_squad: anchor %X (%s, %s)", base,
    tostring(lastName(base)), tostring(wantClub)))

  local hits = scanForQword(base)
  print(string.format("dump_squad: %d pointer(s) to the anchor", #hits))

  -- Collect distinct candidate runs first, so we scan each start only once.
  local candidates, seen = {}, {}
  for _, h in ipairs(hits) do
    local first, last = runAround(h)
    if not seen[first] then
      seen[first] = true
      local count = (last - first) / 8 + 1
      if count >= MIN_SQUAD then
        -- Majority rather than unanimity: a single loanee or a stale slot
        -- shouldn't veto an otherwise-correct squad list. Requiring every
        -- member to match produced zero candidates on a run where the squad
        -- list was plainly there.
        local same = 0
        for i = 0, count - 1 do
          if clubName(rq(first + i * 8)) == wantClub then same = same + 1 end
        end
        if same * 10 >= count * 7 then
          candidates[#candidates + 1] = { addr = first, count = count }
        end
      end
    end
  end
  print(string.format("dump_squad: %d candidate run(s)", #candidates))

  -- Longest run, as the fallback.
  local best = nil
  for _, c in ipairs(candidates) do
    if best == nil or c.count > best.count then best = { addr = c.addr, count = c.count, source = "run" } end
  end

  -- Prefer a vector-backed candidate. One scan each, so bound the work.
  table.sort(candidates, function(a, b) return a.count > b.count end)
  for i = 1, math.min(#candidates, MAX_HEADER_SCANS) do
    local c = candidates[i]
    local count = vectorCountFor(c.addr)
    if count then
      best = { addr = c.addr, count = count, source = "vector" }
      break
    end
  end

  if best then
    print(string.format("dump_squad: squad array at %X, %d players (via %s)",
      best.addr, best.count, best.source))
  else
    print("dump_squad: no squad-shaped run found")
  end
  return best
end

-- Read a squad straight out of a known std::vector header
-- ({begin, end, capacity_end}), which is exact rather than heuristic: the
-- element count comes from the container itself, so there's no truncation and
-- no over-extension past the end.
--
-- The catch is knowing the header address. It's a fresh heap allocation each
-- launch and nothing points at it, so today you have to find it once per run
-- (see docs/phase1-notes.md). Once a static pointer path exists this becomes
-- the primary entry point and the scanning path below can retire.
function squad_from_vector(headerHex)
  local hdr = tonumber(headerHex, 16)
  if not hdr then print("dump_squad: bad header address") return nil end
  local b, e, cap = rq(hdr), rq(hdr + 8), rq(hdr + 16)
  if not (b and e and cap) or e <= b or (e - b) % 8 ~= 0 or cap < e then
    print(string.format("dump_squad: %X is not a valid vector header", hdr))
    return nil
  end
  local count = (e - b) / 8
  print(string.format("dump_squad: vector %X -> array %X, %d players", hdr, b, count))
  return { addr = b, count = count, source = "vector-header" }
end

function dump_squad(arrOverride)
  local arr = arrOverride or find_squad_array()
  if not arr then return nil end
  local players = {}
  for i = 0, arr.count - 1 do
    local p = rq(arr.addr + i * 8)
    players[#players + 1] = dump_player_at(p)
  end
  return {
    mode = "full",
    squad_array = string.format("%X", arr.addr),
    squad_count = arr.count,
    squad_source = arr.source,  -- "vector" (header-confirmed) or "run" (heuristic)
    players = players,
  }
end

-- dump_squad_to_file()              -- locate the array by scanning (heuristic)
-- dump_squad_to_file(path, "6B7CC8C0") -- read a known vector header (exact)
function dump_squad_to_file(path, headerHex)
  path = path or DEFAULT_OUT
  local arr = headerHex and squad_from_vector(headerHex) or nil
  if headerHex and not arr then return false end
  local data = dump_squad(arr)
  if not data then return false end
  local json = jsonEncode(data)
  local f = io.open(path, "w")
  if not f then print("dump_squad: could not write " .. path) return false end
  f:write(json)
  f:close()
  print(string.format("dump_squad: wrote %d players (%d bytes) to %s",
    data.squad_count, #json, path))
  return true
end
