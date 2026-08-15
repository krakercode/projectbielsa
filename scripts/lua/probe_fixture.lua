-- Phase 1 exploration: find the fixture/result structure.
--
-- Motivation: the league table resisted three different approaches -- it is not
-- an array of club pointers, there is no P/W/D/L tuple near a club pointer, and
-- there is no such tuple inside the club object's first 8KB. A strong
-- explanation is that FM DERIVES the table from results rather than storing it.
-- If so the fixture list is the real target, and the table falls out of it.
--
-- Method: a fixture must reference two clubs. Scan for pointers to two clubs
-- known to be playing each other, then find places where those pointers sit
-- close together. That pair is a fixture record; the surrounding integers
-- should contain the scoreline and date.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_fixture.lua]])
--   probe_fixture()
--
-- Writes data/snapshots/fixture_probe.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUT = REPO .. [[\data\snapshots\fixture_probe.json]]

-- Man City v Everton, scheduled 3 Oct 2020 17:30.
local HOME = { name = "Man City", addr = 0x975B0CE8 }
local AWAY = { name = "Everton",  addr = 0x975AE420 }

local NEAR = 128       -- bytes apart to count as the same fixture record
local CONTEXT = 64     -- bytes either side to dump
local MAX_REPORT = 20

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function r16(a)
  local ok, v = pcall(readSmallInteger, a)
  if ok then return v end
  return nil
end

local function r32(a)
  local ok, v = pcall(readInteger, a)
  if ok then return v end
  return nil
end

local function readStr(addr)
  if not addr then return nil end
  local ok, s = pcall(readString, addr, 64, false)
  if ok and s and #s > 0 then return s end
  return nil
end

local function clubName(p)
  local q = rq(p + 0xB8)
  return q and readStr(q + 0x4) or nil
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

local function jesc(s) return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') end

function probe_fixture()
  print(string.format("probe_fixture: %s (%s) v %s (%s)",
    HOME.name, tostring(clubName(HOME.addr)), AWAY.name, tostring(clubName(AWAY.addr))))

  local homeHits = scanForQword(HOME.addr)
  local awayHits = scanForQword(AWAY.addr)
  print(string.format("probe_fixture: %d home pointer(s), %d away pointer(s)",
    #homeHits, #awayHits))

  -- Index away hits for quick proximity lookup.
  table.sort(awayHits)

  local pairs_, reported = {}, 0
  for _, h in ipairs(homeHits) do
    for _, a in ipairs(awayHits) do
      local delta = a - h
      if delta >= -NEAR and delta <= NEAR and delta ~= 0 then
        reported = reported + 1
        if reported <= MAX_REPORT then
          print(string.format("--- pair: home %X, away %X (delta %+d)", h, a, delta))
          local base = math.min(h, a)
          local vals = {}
          for off = -CONTEXT, CONTEXT, 4 do
            vals[#vals + 1] = string.format('{"o":%d,"i32":%s,"i16":%s}',
              off, tostring(r32(base + off) or "null"), tostring(r16(base + off) or "null"))
          end
          pairs_[#pairs_ + 1] = string.format(
            '{"home":"%X","away":"%X","delta":%d,"base":"%X","ctx":[%s]}',
            h, a, delta, base, table.concat(vals, ","))
        end
      end
    end
  end

  local f = io.open(OUT, "w")
  if f then
    f:write(string.format('{"home":"%s","away":"%s","pairs":[%s]}',
      jesc(HOME.name), jesc(AWAY.name), table.concat(pairs_, ",")))
    f:close()
  end
  print(string.format("probe_fixture: %d co-located pair(s) -> %s", reported, OUT))
end
