#!/usr/bin/env node
// Build a static RTTI class/vtable index from fm.exe without attaching to FM.
// Useful for turning a semantic class family (for example RESPONSE) into the
// vtable signatures that scan_mem.ps1 can locate in live writable memory.

const fs = require('fs');
const path = require('path');

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const contains = arg('--contains', '').toUpperCase();
const exe = arg('--exe', 'D:/SteamLibrary/steamapps/common/Football Manager 2021/fm.exe');
const out = arg('--out', '');

if (!fs.existsSync(exe)) {
  console.error(`fm.exe not found: ${exe}`);
  process.exit(1);
}
const buf = fs.readFileSync(exe);
const pe = buf.readUInt32LE(0x3c);
const sectionCount = buf.readUInt16LE(pe + 6);
const optSize = buf.readUInt16LE(pe + 20);
const opt = pe + 24;
const magic = buf.readUInt16LE(opt);
if (magic !== 0x20b) throw new Error('expected PE32+ executable');
const imageBase = buf.readBigUInt64LE(opt + 24);
const sectionTable = opt + optSize;
const sections = [];
for (let i = 0; i < sectionCount; i++) {
  const o = sectionTable + i * 40;
  sections.push({
    name: buf.subarray(o, o + 8).toString('ascii').replace(/\0.*/, ''),
    virtualSize: buf.readUInt32LE(o + 8),
    virtualAddress: buf.readUInt32LE(o + 12),
    rawSize: buf.readUInt32LE(o + 16),
    rawPointer: buf.readUInt32LE(o + 20),
  });
}
function rawToRva(raw) {
  const s = sections.find((x) => raw >= x.rawPointer && raw < x.rawPointer + x.rawSize);
  return s ? s.virtualAddress + (raw - s.rawPointer) : null;
}
function rvaToRaw(rva) {
  const s = sections.find((x) => rva >= x.virtualAddress && rva < x.virtualAddress + x.rawSize);
  return s ? s.rawPointer + (rva - s.virtualAddress) : null;
}

// TypeDescriptor layout on MSVC x64 is two pointers followed by the mangled
// class name. Collect plausible .?AV / .?AU names first; COL validation below
// discards ordinary strings that only happen to look similar.
const tdByRva = new Map();
for (let at = 0; at < buf.length - 5; at++) {
  if (buf[at] !== 0x2e || buf[at + 1] !== 0x3f || buf[at + 2] !== 0x41) continue;
  if (buf[at + 3] !== 0x56 && buf[at + 3] !== 0x55) continue;
  let end = at + 4;
  while (end < buf.length && buf[end] !== 0 && end - at < 512) end++;
  if (end >= buf.length || end - at >= 512) continue;
  const name = buf.subarray(at, end).toString('ascii');
  if (contains && !name.toUpperCase().includes(contains)) continue;
  const tdRaw = at - 16;
  if (tdRaw < 0) continue;
  const tdRva = rawToRva(tdRaw);
  if (tdRva !== null) tdByRva.set(tdRva >>> 0, name);
}

// A CompleteObjectLocator has signature 1, a TypeDescriptor RVA at +12 and
// its own RVA at +20. Scan linearly and keep only COLs referring to our names.
const cols = new Map();
for (const s of sections) {
  const start = s.rawPointer;
  const end = Math.min(buf.length, s.rawPointer + s.rawSize);
  for (let o = start; o + 24 <= end; o += 4) {
    if (buf.readUInt32LE(o) !== 1) continue;
    const tdRva = buf.readUInt32LE(o + 12);
    const name = tdByRva.get(tdRva);
    if (!name) continue;
    const colRva = rawToRva(o);
    if (colRva === null || buf.readUInt32LE(o + 20) !== (colRva >>> 0)) continue;
    cols.set(imageBase + BigInt(colRva), { name, colRva, objectOffset: buf.readUInt32LE(o + 4), cdOffset: buf.readUInt32LE(o + 8) });
  }
}

// vtable[-8] is the COL pointer. Scan qwords once and map matching COLs to
// the following address, which is the vtable start used in live objects.
const rows = [];
for (const s of sections) {
  const start = s.rawPointer + ((8 - (s.rawPointer % 8)) % 8);
  const end = Math.min(buf.length, s.rawPointer + s.rawSize);
  for (let o = start; o + 16 <= end; o += 8) {
    const col = cols.get(buf.readBigUInt64LE(o));
    if (!col) continue;
    const vtRva = rawToRva(o + 8);
    if (vtRva === null) continue;
    rows.push({ name: col.name, object_offset: col.objectOffset, cd_offset: col.cdOffset, vtable_rva: `0x${vtRva.toString(16)}`, vtable: `0x${(imageBase + BigInt(vtRva)).toString(16)}` });
  }
}
rows.sort((a, b) => a.name.localeCompare(b.name) || a.vtable.localeCompare(b.vtable));
const result = {
  exe: path.resolve(exe),
  image_base: `0x${imageBase.toString(16)}`,
  contains: contains || null,
  count: rows.length,
  rows,
};
const text = JSON.stringify(result, null, 2);
if (out) {
  fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  fs.writeFileSync(out, text + '\n');
  console.log(`${rows.length} RTTI vtable(s) -> ${out}`);
} else {
  console.log(text);
}
