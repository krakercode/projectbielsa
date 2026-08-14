-- Diagnostic for dump_squad.lua's array detection.
--
-- Answers two questions in one run:
--   1. Is the std::vector header found on 2026-08-14 (0x6B7CC8C0) still valid,
--      and does it still describe the senior squad? That tells us whether the
--      vector persists across UI navigation or is rebuilt with the screen.
--   2. For the current anchor, what does every pointer hit actually look like --
--      run length and how many members share the anchor's club? That shows
--      whether candidates are being lost to truncation or to the club filter.
--
-- Usage:
--   dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\diag_squad.lua]])
--   diag_squad()

local REPO = [[C:\Users\User\Desktop\projectbielsa]]
dofile(REPO .. [[\scripts\lua\dump_state.lua]])

local KNOWN_VECTOR = 0x6B7CC8C0

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

function diag_squad()
  -- (1) is the previously-found vector header still live?
  local b, e, cap = rq(KNOWN_VECTOR), rq(KNOWN_VECTOR + 8), rq(KNOWN_VECTOR + 16)
  print(string.format("known vector %X: begin=%s end=%s cap=%s",
    KNOWN_VECTOR, tostring(b and string.format("%X", b)),
    tostring(e and string.format("%X", e)), tostring(cap and string.format("%X", cap))))
  if b and e and e > b and (e - b) % 8 == 0 then
    local n = (e - b) / 8
    print(string.format("  -> %d elements", n))
    local names = {}
    for i = 0, math.min(n, 40) - 1 do
      local p = rq(b + i * 8)
      names[#names + 1] = string.format("%s(%s)", tostring(lastName(p)), tostring(clubName(p)))
    end
    print("  " .. table.concat(names, ", "))
  else
    print("  -> no longer a valid vector")
  end

  -- (2) what do the current anchor's hits look like?
  local anchor = rq(getAddress("pCurrentPlayer"))
  if anchor == nil or anchor == 0 then print("no player selected") return end
  local wantClub = clubName(anchor)
  print(string.format("anchor %X (%s, %s)", anchor, tostring(lastName(anchor)), tostring(wantClub)))

  local hits = scanForQword(anchor)
  print(string.format("%d hit(s):", #hits))
  for _, h in ipairs(hits) do
    local first, last = h, h
    for i = 1, 256 do if isPlayer(rq(h - i * 8)) then first = h - i * 8 else break end end
    for i = 1, 256 do if isPlayer(rq(h + i * 8)) then last = h + i * 8 else break end end
    local count = (last - first) / 8 + 1
    if count >= 4 then
      local same, other = 0, nil
      for i = 0, count - 1 do
        local c = clubName(rq(first + i * 8))
        if c == wantClub then same = same + 1 elseif not other then other = c end
      end
      print(string.format("  hit %X: run %X..%X len=%d sameClub=%d/%d firstOther=%s",
        h, first, last, count, same, count, tostring(other)))
    end
  end
end
