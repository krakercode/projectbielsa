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

local MIN_SQUAD = 8      -- shorter runs than this aren't a squad
local MAX_WALK = 256     -- don't walk further than this in either direction

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

-- Returns {startAddr, count} for the best squad-looking run, or nil.
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

  local best, seen = nil, {}
  for _, h in ipairs(hits) do
    local first, last = runAround(h)
    if not seen[first] then
      seen[first] = true
      local count = (last - first) / 8 + 1
      if count >= MIN_SQUAD then
        -- every member must play for the same club, else it's a mixed list
        local sameClub = true
        for i = 0, count - 1 do
          if clubName(rq(first + i * 8)) ~= wantClub then sameClub = false break end
        end
        if sameClub and (best == nil or count > best.count) then
          best = { addr = first, count = count }
        end
      end
    end
  end

  if best then
    print(string.format("dump_squad: squad array at %X, %d players", best.addr, best.count))
  else
    print("dump_squad: no squad-shaped run found")
  end
  return best
end

function dump_squad()
  local arr = find_squad_array()
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
    players = players,
  }
end

function dump_squad_to_file(path)
  path = path or DEFAULT_OUT
  local data = dump_squad()
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
