-- Dump the 20/20 club arrays found by find_row_array.lua, with their payloads.
--
-- WHY THIS IS THE INTERESTING ONE
-- find_row_array found several arrays holding pointers to all 20 BBD9 per-club
-- records at a STRIDE OF 16. A pointer is 8 bytes, so every entry carries 8 more
-- bytes of payload alongside the pointer. That is exactly the shape of a sortable
-- league-table entry: {record*, sortkey/stats}.
--
-- One of the arrays is also in neither alphabetical nor reverse-alphabetical
-- order, which means something has already ranked it -- and the on-screen table
-- is the obvious candidate ranking.
--
-- This dumps each array plus context so the payload can be matched against the
-- real table offline, in Node, rather than guessed at here.
--
-- Usage from the CE Lua Engine:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\dump_club_arrays.lua]])
--   dump_club_arrays()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
local OUT  = REPO .. [[\data\snapshots\club_arrays.json]]

-- BBD9 per-club records -> club name, so array slots can be resolved.
BBD9 = {
  [0xBBD953F8]="Arsenal",   [0xBBD954B0]="Aston Villa", [0xBBD95F78]="Brighton",
  [0xBBD96258]="Burnley",   [0xBBD96818]="Chelsea",     [0xBBD970B8]="Crystal Palace",
  [0xBBD975C0]="Everton",   [0xBBD978A0]="Fulham",      [0xBBD984D8]="Leeds",
  [0xBBD98648]="Leicester", [0xBBD98870]="Liverpool",   [0xBBD98A98]="Man City",
  [0xBBD98B50]="Man Utd",   [0xBBD99110]="Newcastle",   [0xBBD99F70]="Sheff Utd",
  [0xBBD9A308]="Southampton",[0xBBD9ADD0]="Tottenham",  [0xBBD9B168]="West Brom",
  [0xBBD9B220]="West Ham",  [0xBBD9B5B8]="Wolves",
}

-- The 20/20 arrays from data/snapshots/row_array.log.
ARRAYS = {
  { name = "A_5424",  base = 0x54247A0,  stride = 16 },
  { name = "B_54751", base = 0x54751DC0, stride = 16 },
  { name = "C_945BA", base = 0x945BAAC0, stride = 16 },
}

local ENTRIES = 20
local PAD     = 4     -- entries of context before/after

local function rq(a)
  local ok, v = pcall(readQword, a)
  if ok then return v end
  return nil
end

local function rbyte(a)
  local ok, v = pcall(readBytes, a, 1, false)
  if ok and v then return v end
  return 0
end

function dump_club_arrays()
  local parts = {}
  for _, arr in ipairs(ARRAYS) do
    print(string.format("\n=== %s base=%X stride=%d ===", arr.name, arr.base, arr.stride))
    local entries = {}
    for i = -PAD, ENTRIES + PAD - 1 do
      local slot = arr.base + i * arr.stride
      local ptr  = rq(slot)
      local club = ptr and BBD9[ptr] or nil
      -- every byte of the entry, so the payload can be decoded any width
      local bytes = {}
      for b = 0, arr.stride - 1 do bytes[#bytes+1] = tostring(rbyte(slot + b)) end
      if club then
        print(string.format("  [%2d] %X -> %-15s payload=%X",
          i, slot, club, rq(slot + 8) or 0))
      end
      entries[#entries+1] = string.format(
        '{"i":%d,"slot":"%X","ptr":"%s","club":%s,"bytes":[%s]}',
        i, slot, ptr and string.format("%X", ptr) or "0",
        club and ('"' .. club .. '"') or "null",
        table.concat(bytes, ","))
    end
    parts[#parts+1] = string.format('{"name":"%s","base":"%X","stride":%d,"entries":[%s]}',
      arr.name, arr.base, arr.stride, table.concat(entries, ","))
  end

  local f = io.open(OUT, "w")
  if not f then print("dump_club_arrays: cannot write " .. OUT) return end
  f:write('{"arrays":[' .. table.concat(parts, ",") .. ']}')
  f:close()
  print("\ndump_club_arrays: wrote " .. OUT)
end
