-- Walk a suspected array of Club* pointers and print every entry in order.
--
-- Used to confirm whether a candidate region is a league's club list: an
-- English Premier Division array should read out as exactly the 20 top-flight
-- clubs, in table or registration order, with nothing else mixed in.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_club_array.lua]])
--   dump_club_array("B8599090")        -- walks outward from here, stride 8
--   dump_club_array("B8599090", 8, 64) -- explicit stride (bytes) and max walk
--
-- Writes data/snapshots/club_array_<addr>.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUTDIR = REPO .. [[\data\snapshots\]]

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

local function clubFullName(p)
  local q = rq(p + 0xB8)
  return q and readStr(q + 0x4) or nil
end

local function clubShortName(p)
  local q = rq(p + 0xC0)
  return q and readStr(q + 0x4) or nil
end

local function isClub(p)
  if p == nil or p < 0x10000 or p > 0x7FFFFFFFFFFF then return false end
  local vt = rq(p)
  if vt == nil or vt == 0 then return false end
  return printable(clubFullName(p)) and printable(clubShortName(p))
end

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function dump_club_array(addrHex, stride, maxWalk)
  stride = stride or 8
  maxWalk = maxWalk or 64
  local center = tonumber(addrHex, 16)
  if not center then print("bad address") return nil end
  if not isClub(rq(center)) then
    print(string.format("dump_club_array: %X does not hold a club pointer", center))
    return nil
  end

  local first, last = center, center
  for i = 1, maxWalk do
    if isClub(rq(center - i * stride)) then first = center - i * stride else break end
  end
  for i = 1, maxWalk do
    if isClub(rq(center + i * stride)) then last = center + i * stride else break end
  end

  local rows, n = {}, 0
  print(string.format("dump_club_array: %X .. %X, stride %d", first, last, stride))
  for a = first, last, stride do
    local p = rq(a)
    local name = clubFullName(p)
    n = n + 1
    print(string.format("  %2d  %X -> %X  %s", n, a, p, tostring(name)))
    rows[#rows + 1] = string.format('{"i":%d,"slot":"%X","club":"%X","name":"%s"}',
      n, a, p, jesc(name))
  end

  local path = OUTDIR .. "club_array_" .. addrHex .. ".json"
  local f = io.open(path, "w")
  if f then
    f:write(string.format('{"first":"%X","last":"%X","stride":%d,"count":%d,"entries":[%s]}',
      first, last, stride, n, table.concat(rows, ",")))
    f:close()
  end
  print(string.format("dump_club_array: %d entries -> %s", n, path))
  return { first = first, last = last, count = n }
end
