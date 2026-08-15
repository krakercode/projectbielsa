-- Phase 1 exploration: find the structure behind a league table.
--
-- First attempt anchored on a single club and inspected a +/-48 slot window.
-- That was too small: a 20-row table at the observed 32-byte stride spans 640
-- bytes, and no window came back purely Premier League -- every group mixed
-- divisions, so they were general club indexes rather than a table.
--
-- This version uses the trick that worked for the squad: scan for pointers to
-- SEVERAL known clubs of the same league and look for a region where they all
-- appear. A league table must contain every one of its clubs, so a cluster
-- holding 5+ of them is a strong candidate; a general club index will hold them
-- too but interleaved with clubs from other divisions, which the report makes
-- visible.
--
-- Club record addresses are stable within a session and can be harvested from
-- data/snapshots/league_probe.json produced by the earlier run, or by opening
-- each club's page in FM and reading pCurrentClub.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_league.lua]])
--   probe_league()
--
-- Writes data/snapshots/league_cluster.json.

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local OUT = REPO .. [[\data\snapshots\league_cluster.json]]

-- Known Premier League club records for this session. Regenerate after any
-- restart: these are heap addresses.
local KNOWN = {
  { name = "Arsenal",       addr = 0x975AA208 },
  { name = "Aston Villa",   addr = 0x975AA370 },
  { name = "Chelsea",       addr = 0x975AC968 },
  { name = "Everton",       addr = 0x975AE420 },
  { name = "Leicester",     addr = 0x975B0478 },
  { name = "Man City",      addr = 0x975B0CE8 },
  { name = "Tottenham",     addr = 0x975B51D0 },
  { name = "Wolves",        addr = 0x975B6148 },
}

local CLUSTER_BYTES = 4096   -- how close hits must be to count as one region
local MIN_DISTINCT = 5       -- distinct clubs needed to report a cluster

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

local function clubFullName(p)
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

function probe_league()
  -- Step 1: where is each known club pointed at from?
  local all = {}
  for _, c in ipairs(KNOWN) do
    local hits = scanForQword(c.addr)
    print(string.format("probe_league: %-12s %d pointer(s)", c.name, #hits))
    for _, h in ipairs(hits) do all[#all + 1] = { at = h, club = c.name } end
  end
  table.sort(all, function(a, b) return a.at < b.at end)
  print(string.format("probe_league: %d total hits", #all))

  -- Step 2: cluster by proximity.
  local clusters, cur = {}, nil
  for _, e in ipairs(all) do
    if cur and (e.at - cur.last) <= CLUSTER_BYTES then
      cur.items[#cur.items + 1] = e
      cur.last = e.at
    else
      if cur then clusters[#clusters + 1] = cur end
      cur = { items = { e }, first = e.at, last = e.at }
    end
  end
  if cur then clusters[#clusters + 1] = cur end

  -- Step 3: report clusters holding enough distinct clubs.
  local reported = {}
  for _, cl in ipairs(clusters) do
    local seen, n = {}, 0
    for _, it in ipairs(cl.items) do
      if not seen[it.club] then seen[it.club] = true n = n + 1 end
    end
    if n >= MIN_DISTINCT then
      -- spacing between consecutive hits tells us the row stride
      local gaps = {}
      for i = 2, #cl.items do gaps[#gaps + 1] = cl.items[i].at - cl.items[i - 1].at end
      local gapCount = {}
      for _, g in ipairs(gaps) do gapCount[g] = (gapCount[g] or 0) + 1 end
      local stride, best = nil, 0
      for g, k in pairs(gapCount) do if k > best then stride, best = g, k end end

      print(string.format("  cluster %X..%X: %d hits, %d distinct clubs, dominant gap %s bytes (%d/%d)",
        cl.first, cl.last, #cl.items, n, tostring(stride), best, #gaps))

      local parts = {}
      for _, it in ipairs(cl.items) do
        parts[#parts + 1] = string.format('{"at":"%X","club":"%s"}', it.at, jesc(it.club))
      end
      reported[#reported + 1] = string.format(
        '{"first":"%X","last":"%X","hits":%d,"distinct":%d,"stride":%s,"items":[%s]}',
        cl.first, cl.last, #cl.items, n, tostring(stride or "null"), table.concat(parts, ","))
    end
  end

  local f = io.open(OUT, "w")
  if f then f:write('{"clusters":[' .. table.concat(reported, ",") .. ']}') f:close() end
  print(string.format("probe_league: %d cluster(s) with >=%d distinct clubs -> %s",
    #reported, MIN_DISTINCT, OUT))
end
