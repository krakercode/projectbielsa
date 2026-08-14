-- Phase 1: locate the club's own player list.
--
-- The arrays found by scanning for pointers to known players live in what
-- looks like a UI/list arena (the same region holds unrelated lists, e.g. a
-- national squad), so they're not a durable handle on "this club's players".
-- The club object itself is reachable from any player record --
-- club = [[player + 0x88] + 0x30] -- so this walks the club object looking for
-- a member that points at an array of player pointers.
--
-- Recognises two common container shapes:
--   * pointer + separate count
--   * begin/end pair (std::vector-like), count = (end - begin) / 8
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\find_club_players.lua]])
--   find_club_players()
--
-- Writes data/snapshots/club_scan.json.

local OUT = [[C:\Users\User\Desktop\projectbielsa\data\snapshots\club_scan.json]]
local CLUB_SCAN_BYTES = 0x1000

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

local function chain(base, offsets)
  local addr = base
  for i, off in ipairs(offsets) do
    if i == 1 then
      addr = addr + off
    else
      local ptr = rq(addr)
      if ptr == nil or ptr == 0 then return nil end
      addr = ptr + off
    end
  end
  return addr
end

local function printable(s)
  if not s or #s == 0 then return false end
  for i = 1, #s do
    local b = s:byte(i)
    if b < 32 or b > 126 then return false end
  end
  return true
end

local function isPlayer(p)
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return false end
  local vt = rq(p)
  if vt == nil or vt == 0 then return false end
  local last = readStr(chain(p, { 0x2D0, 0x0, 0x4 }))
  if not printable(last) then return false end
  local okca, ca = pcall(readSmallInteger, p + 0x1FC)
  return okca and ca ~= nil and ca >= 1 and ca <= 200
end

local function playerName(p)
  local first = readStr(chain(p, { 0x2C8, 0x0, 0x4 })) or ""
  local last = readStr(chain(p, { 0x2D0, 0x0, 0x4 })) or ""
  return (first .. " " .. last)
end

-- How many of the first `n` slots at `arr` look like player records?
local function playerRunLength(arr, maxN)
  if arr == nil or arr < 0x10000 or arr > 0x7FFFFFFFFFFF then return 0 end
  local n = 0
  for i = 0, maxN - 1 do
    if isPlayer(rq(arr + i * 8)) then n = n + 1 else break end
  end
  return n
end

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function find_club_players()
  local base = rq(getAddress("pCurrentPlayer"))
  if base == nil or base == 0 then print("no player selected") return end

  -- chain() returns the address a value sits at, so the club object pointer is
  -- one more dereference: club = [[player + 0x88] + 0x30].
  local clubSlot = chain(base, { 0x88, 0x30 })
  local club = clubSlot and rq(clubSlot) or nil
  if club == nil or club == 0 then print("could not resolve club object") return end

  local clubName = readStr(chain(club, { 0xB8, 0x4 })) or "?"
  print(string.format("player %X -> club object %X (%s)", base, club, clubName))

  local findings = {}
  for off = 0, CLUB_SCAN_BYTES - 8, 8 do
    local v = rq(club + off)
    if v and v > 0x10000 and v < 0x7FFFFFFFFFFF then
      -- shape A: club+off points straight at an array of player pointers
      local run = playerRunLength(v, 64)
      if run >= 3 then
        findings[#findings + 1] = string.format(
          '{"shape":"ptr","clubOffset":"%X","array":"%X","runLen":%d,"first":"%s","second":"%s"}',
          off, v, run, jesc(playerName(rq(v))), jesc(playerName(rq(v + 8))))
        print(string.format("  club+0x%X -> array %X, %d players (%s, ...)",
          off, v, run, playerName(rq(v))))
      end

      -- shape B: begin/end pair at club+off / club+off+8
      local e = rq(club + off + 8)
      if e and e > v and (e - v) % 8 == 0 and (e - v) <= 8 * 4096 then
        local count = (e - v) / 8
        local run2 = playerRunLength(v, math.min(count, 64))
        if run2 >= 3 and run2 == math.min(count, 64) then
          findings[#findings + 1] = string.format(
            '{"shape":"beginEnd","clubOffset":"%X","begin":"%X","end":"%X","count":%d,"first":"%s"}',
            off, v, e, count, jesc(playerName(rq(v))))
          print(string.format("  club+0x%X -> vector[%d] %X..%X (%s, ...)",
            off, count, v, e, playerName(rq(v))))
        end
      end
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write(string.format('{"player":"%X","club":"%X","clubName":"%s","findings":[%s]}',
      base, club, jesc(clubName), table.concat(findings, ",")))
    f:close()
  end
  print("wrote " .. OUT .. " (" .. #findings .. " candidate container(s))")
end
