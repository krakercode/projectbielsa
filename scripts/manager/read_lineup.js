// Parse FM's team-selection list out of a raw memory dump.
//
// WHAT THIS READS
// A structure holding the selected XI followed by the bench, IN POSITIONAL ORDER
// (GK, DR, DCR, DCL, DL, DM, MCL, MCR, AMR, AML, STC, then subs). Each entry is a
// variable-length serialized record: a 4-byte player UID, then the first and last
// name as inline zero-terminated strings, then more fields. The UID appears twice
// per record.
//
// HOW IT WAS FOUND (docs/session-log/2026-08-16-*)
// Team selection is NOT a field on the player record -- swapping a starter for a
// sub changed zero bytes across all 23 player records. It is a separate structure.
// Scanning for a player's UID while he was selected, then again after benching
// him, isolated slots that track "who plays at DL"; dumping around them revealed
// this list.
//
// IMPORTANT CAVEAT -- READ ONLY, AND PROBABLY NOT AUTHORITATIVE
// FM keeps ELEVEN identical copies of this structure, and the records carry inline
// display names. That is the shape of a UI data model rather than the canonical
// tactic object. It is trustworthy for READING the current selection (it tracked
// every swap correctly), but writing into it would very likely change only what is
// drawn, not what the match engine uses. Phase 2's write layer needs the
// authoritative store, which is still unlocated. Do not build set_lineup() on this.
//
//   node scripts/manager/read_lineup.js data/snapshots/xi_region.json
//
// Produce the dump with:
//   powershell -File scripts/win/read_mem.ps1 -Address <base> -Length 2048 \
//     -AsJson data/snapshots/xi_region.json

const fs = require('fs');

// Positional slots in the order FM serialises them.
const SLOTS = ['GK', 'DR', 'DCR', 'DCL', 'DL', 'DM', 'MCL', 'MCR', 'AMR', 'AML', 'STC'];

function loadDump(path) {
  const raw = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^﻿/, ''));
  const arr = Array.isArray(raw.bytes) ? raw.bytes : raw.bytes.value;
  return { base: parseInt(raw.address, 16), buf: Buffer.from(arr) };
}

// The strings are LENGTH-PREFIXED, not zero-terminated. Scanning for a NUL runs
// straight past the name into the next length prefix (e.g. "Emiliano" is followed
// by 09 00 00 00, and 0x09 is not zero), so always slice by the stated length.
function readStr(buf, off, len) {
  if (off + len > buf.length) return null;
  return buf.slice(off, off + len).toString('utf8');
}

const NAME_RE = /^[A-Za-zÀ-ÿ' .\-]+$/;

// Record layout, decoded from a live dump:
//   +0x00  u32  player UID
//   +0x04  u32  length of first name
//   +0x08  ..   first name, UTF-8, zero-terminated
//   +N     u32  length of last name
//   +N+4   ..   last name
// The UID then repeats later in the same record, which is why the scan for a
// player's UID returned two hits per entry.
function parseEntries(buf, base) {
  const out = [];
  let o = 0;
  while (o + 12 <= buf.length) {
    const uid = buf.readUInt32LE(o);
    // FM player UIDs in this save run from ~5e6 to ~9e7
    if (uid < 1_000_000 || uid > 99_999_999) { o++; continue; }

    const firstLen = buf.readUInt32LE(o + 4);
    if (firstLen < 2 || firstLen > 24) { o++; continue; }
    const first = readStr(buf, o + 8, firstLen);
    if (!first || !NAME_RE.test(first)) { o++; continue; }

    const lastLenOff = o + 8 + firstLen;
    if (lastLenOff + 4 > buf.length) { o++; continue; }
    const lastLen = buf.readUInt32LE(lastLenOff);
    if (lastLen < 2 || lastLen > 28) { o++; continue; }
    const last = readStr(buf, lastLenOff + 4, lastLen);
    if (!last || !NAME_RE.test(last)) { o++; continue; }

    out.push({ off: o, addr: (base + o).toString(16).toUpperCase(), uid, first, last });
    o = lastLenOff + 4 + lastLen;   // jump past this record, skipping its repeated UID
  }
  return out;
}

function main() {
  const path = process.argv[2] || 'data/snapshots/xi_region.json';
  const { base, buf } = loadDump(path);
  const entries = parseEntries(buf, base);

  if (!entries.length) {
    console.error('no selection records found in ' + path);
    process.exit(2);
  }

  console.log('selection list parsed from ' + path);
  console.log('base 0x' + base.toString(16).toUpperCase() + ', ' + entries.length + ' entries\n');
  entries.forEach((e, i) => {
    const slot = i < SLOTS.length ? SLOTS[i] : 'S' + (i - SLOTS.length + 1);
    console.log(
      '  ' + slot.padEnd(4) +
      '  ' + (e.first + ' ' + e.last).padEnd(26) +
      '  uid=' + String(e.uid).padStart(9) +
      '  @' + e.addr
    );
  });

  const xi = entries.slice(0, 11);
  console.log('\nstarting XI: ' + xi.map(e => e.last).join(', '));
}

main();
