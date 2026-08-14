// One-off generator: turns cheat-table/fields.json (produced by parse_ct.js)
// into scripts/lua/dump_state.lua -- a real Lua script for Cheat Engine that
// reads every field the vendored table exposes for the currently-selected
// player/club/staff and serializes it to JSON.
//
// Regenerate with: node generate_dump_lua.js
// (after re-running parse_ct.js if fm.CT ever changes)

const fs = require('fs');
const path = require('path');

const fields = require('./fields.json');

function luaStringLiteral(s) {
  return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

function fieldsToLua(list) {
  const lines = [];
  for (const f of list) {
    const pathLua = '{' + f.path.map(luaStringLiteral).join(', ') + '}';
    const offsetsLua = '{' + f.offsets.map(o => '0x' + o.toUpperCase()).join(', ') + '}';
    lines.push(`    { path = ${pathLua}, offsets = ${offsetsLua}, vtype = ${luaStringLiteral(f.varType)} },`);
  }
  return lines.join('\n');
}

const luaFieldTables = Object.keys(fields).map(recordName => {
  const key = recordName.replace(/ /g, '');
  return `FIELDS.${key} = {\n${fieldsToLua(fields[recordName])}\n}`;
}).join('\n\n');

const template = `-- Phase 1: full state dump for the currently-selected player/club/staff.
--
-- AUTO-GENERATED from cheat-table/fm.CT via cheat-table/parse_ct.js +
-- cheat-table/generate_dump_lua.js -- do not hand-edit the field tables below;
-- regenerate instead if fm.CT changes.
--
-- IMPORTANT LIMITATION: this only reads the *currently selected* player, club,
-- and staff member -- one record each, exactly what the base FM21-Cheat-Table
-- exposes. It does NOT walk the full squad list, full club list, or
-- competition tables -- that requires finding the squad-array pointer via a
-- live AOB scan in Cheat Engine (see PLAN.md Phase 1 / docs/phase0-feasibility.md),
-- which hasn't been done yet. Once that pointer is found, extend this file
-- with a loop over the array instead of a single dumpRecord() call per type.
--
-- VERIFIED LIVE 2026-08-14 against a real save (Aston Villa, 27 Jul 2020):
-- every field below reads back and matches what FM shows on the player
-- profile screen. Two things learned in that first live run, both fixed:
--   * Offsets are emitted in APPLICATION order by parse_ct.js, which reverses
--     the order fm.CT stores them in (CE writes <Offsets> innermost-first).
--     Getting this backwards silently nils out every multi-level chain --
--     all names, all contract fields -- while single-offset fields still work.
--   * Strings are plain single-byte, zero-terminated (fm.CT has Unicode=0),
--     so readString(addr, len, false) is correct -- no widechar needed.
--
-- Attribute values here are FM's INTERNAL scale, not the 1-20 the UI shows:
-- displayed = round(internal / 5), e.g. Grealish's Dribbling is 85 internally
-- and 17 on screen. CA/PA are already on their native 1-200 scale. Condition
-- and the reputation fields are 0-10000. Consumers of this JSON must do their
-- own conversion; the dump deliberately stays raw.
--
-- Requires the base table's "-----[==Features==]-----" script to be active
-- first (it allocates the pCurrentPlayer/pCurrentClub/pCurrentStaff globals
-- this script reads from).

local FIELDS = {}

${luaFieldTables}

-- Resolve a chain against an already-known record address. Offsets are in
-- application order (see parse_ct.js): addr = base + o1, then
-- addr = [addr] + oi for each subsequent offset, reading the final address
-- directly without a last dereference.
local function resolveFrom(base, offsets)
  if base == nil or base == 0 then return nil end
  local addr = base
  for i, off in ipairs(offsets) do
    if i == 1 then
      addr = addr + off
    else
      local okp, ptr = pcall(readQword, addr)
      if not okp or ptr == nil or ptr == 0 then return nil end
      addr = ptr + off
    end
  end
  return addr
end

local function resolvePointerChain(symbolName, offsets)
  local ok, sym = pcall(getAddress, symbolName)
  if not ok or sym == nil or sym == 0 then return nil end
  local ok2, addr = pcall(readQword, sym)
  if not ok2 or addr == nil or addr == 0 then return nil end
  for i, off in ipairs(offsets) do
    if i == 1 then
      addr = addr + off
    else
      local okp, ptr = pcall(readQword, addr)
      if not okp or ptr == nil or ptr == 0 then return nil end
      addr = ptr + off
    end
  end
  return addr
end

local function readByType(address, vtype)
  if address == nil then return nil end
  local ok, value = pcall(function()
    if vtype == "Byte" then
      local b = readBytes(address, 1, true)
      return b and b[1] or nil
    elseif vtype == "2 Bytes" then
      return readSmallInteger(address)
    elseif vtype == "4 Bytes" then
      return readInteger(address)
    elseif vtype == "8 Bytes" then
      return readQword(address)
    elseif vtype == "Float" then
      return readFloat(address)
    elseif vtype == "String" then
      return readString(address, 128, false)
    end
    return nil
  end)
  if ok then return value end
  return nil
end

local function setPath(tbl, fieldPath, value)
  local node = tbl
  for i = 1, #fieldPath - 1 do
    local key = fieldPath[i]
    node[key] = node[key] or {}
    node = node[key]
  end
  node[fieldPath[#fieldPath]] = value
end

local function dumpRecord(symbolName, fieldList)
  local ok, sym = pcall(getAddress, symbolName)
  if not ok or sym == nil or sym == 0 then return nil end
  local ok2, base = pcall(readQword, sym)
  if not ok2 or base == nil or base == 0 then return nil end -- nothing currently selected

  local out = {}
  for _, f in ipairs(fieldList) do
    local addr = resolvePointerChain(symbolName, f.offsets)
    local value = readByType(addr, f.vtype)
    setPath(out, f.path, value)
  end
  return out
end

-- Same as dumpRecord, but against a raw record address rather than one of the
-- base table's pCurrent* symbols. This is what lets us dump every player in a
-- squad array, not just the one FM has selected.
local function dumpRecordAt(base, fieldList)
  if base == nil or base == 0 then return nil end
  local out = {}
  for _, f in ipairs(fieldList) do
    setPath(out, f.path, readByType(resolveFrom(base, f.offsets), f.vtype))
  end
  return out
end

-- Exposed so squad-walking scripts can reuse the field tables and readers
-- instead of duplicating the offsets.
FM_FIELDS = FIELDS
FM_dumpRecordAt = dumpRecordAt
FM_resolveFrom = resolveFrom

function dump_player_at(address)
  return dumpRecordAt(address, FIELDS.CurrentPlayer)
end

function dump_current_player()
  return dumpRecord("pCurrentPlayer", FIELDS.CurrentPlayer)
end

function dump_current_club()
  return dumpRecord("pCurrentClub", FIELDS.CurrentClub)
end

function dump_current_staff()
  return dumpRecord("pCurrentStaff", FIELDS.CurrentStaff)
end

-- Minimal JSON encoder (Cheat Engine's Lua has no guaranteed JSON library).
local function jsonEscape(s)
  s = tostring(s)
  s = s:gsub('\\\\', '\\\\\\\\')
  s = s:gsub('"', '\\\\"')
  s = s:gsub('\\n', '\\\\n')
  s = s:gsub('\\r', '\\\\r')
  s = s:gsub('\\t', '\\\\t')
  return s
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false, 0 end
  for i = 1, n do
    if t[i] == nil then return false, n end
  end
  return true, n
end

function jsonEncode(v)
  local t = type(v)
  if v == nil then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    return tostring(v)
  elseif t == "string" then
    return '"' .. jsonEscape(v) .. '"'
  elseif t == "table" then
    local arr, n = isArray(v)
    local parts = {}
    if arr then
      for i = 1, n do parts[#parts + 1] = jsonEncode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, val in pairs(v) do
        parts[#parts + 1] = '"' .. jsonEscape(k) .. '":' .. jsonEncode(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- mode: "full" (implemented) or "restricted" (Phase 5 human-mode masking --
-- not implemented yet; currently falls back to full data with a warning).
function dump_state(mode)
  mode = mode or "full"
  if mode == "restricted" then
    print("[dump_state] WARNING: 'restricted' (human) mode masking not implemented yet (Phase 5) -- returning full data")
  end
  return {
    mode = mode,
    current_player = dump_current_player(),
    current_club = dump_current_club(),
    current_staff = dump_current_staff(),
  }
end

function dump_state_json(mode)
  return jsonEncode(dump_state(mode))
end

-- Writes the JSON snapshot to disk, e.g. dump_state_to_file([[C:\\\\...\\\\data\\\\snapshots\\\\snap1.json]])
function dump_state_to_file(filepath, mode)
  local json = dump_state_json(mode)
  local f = io.open(filepath, "w")
  if not f then
    print("[dump_state_to_file] ERROR: could not open " .. filepath .. " for writing")
    return false
  end
  f:write(json)
  f:close()
  return true
end
`;

fs.writeFileSync(path.join(__dirname, '..', 'scripts', 'lua', 'dump_state.lua'), template);
console.log('Wrote scripts/lua/dump_state.lua');
