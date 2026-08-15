-- Confirm the club-record addresses recorded in dump_club_record.lua are still
-- live in this process, and report a usable breakpoint anchor.
--
-- Why: the league-table hunt is switching from blind scanning to CE's debugger.
-- The plan is to break on a club object's *name pointer* (club+0xB8) while the
-- league table screen renders, on the reasoning that the table must dereference
-- each club to draw its name. That needs a club address known to be valid right
-- now -- the heap moves on every restart.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\probe_club_anchor.lua]])
--   probe_club_anchor()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]

-- Same set as dump_club_record.lua, recorded 3 Oct 2020 in-game.
local CLUBS = {
  { name = "Leicester",   addr = 0x975B0478 },
  { name = "Aston Villa", addr = 0x975AA370 },
  { name = "Man City",    addr = 0x975B0CE8 },
  { name = "Everton",     addr = 0x975AE420 },
}

local NAME_PTR_OFF = 0xB8   -- club -> name object
local NAME_STR_OFF = 0x4    -- name object -> char buffer

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

local function clubName(p)
  local q = rq(p + NAME_PTR_OFF)
  return q and readStr(q + NAME_STR_OFF) or nil
end

function probe_club_anchor()
  print("probe_club_anchor: checking recorded club addresses")
  local live = 0
  for _, c in ipairs(CLUBS) do
    local got = clubName(c.addr)
    local nameptr = rq(c.addr + NAME_PTR_OFF)
    print(string.format("  %-12s %X  namePtr=%s  reads '%s'",
      c.name, c.addr,
      nameptr and string.format("%X", nameptr) or "nil",
      tostring(got)))
    if got then live = live + 1 end
  end

  -- Independent of the recorded list: whatever club is selected right now.
  local ok, sym = pcall(getAddress, "pCurrentClub")
  if ok and sym then
    local cur = rq(sym)
    if cur and cur ~= 0 then
      print(string.format("  pCurrentClub -> %X  reads '%s'",
        cur, tostring(clubName(cur))))
      print(string.format("  BREAKPOINT ANCHOR (name ptr field): %X",
        cur + NAME_PTR_OFF))
    else
      print("  pCurrentClub is 0 -- visit a club screen with the hook enabled")
    end
  else
    print("  pCurrentClub symbol not found -- is the table loaded?")
  end

  print(string.format("probe_club_anchor: %d/%d recorded addresses still live",
    live, #CLUBS))
  if live == #CLUBS then
    print("  -> heap layout unchanged since the league-table session")
  elseif live == 0 then
    print("  -> all stale; FM has restarted, re-derive from pCurrentClub")
  else
    print("  -> PARTIAL. Do not trust the recorded list.")
  end
end
