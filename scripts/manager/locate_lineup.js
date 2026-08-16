// Locate FM's team-selection list from cold, with no hardcoded addresses and no
// Cheat Engine.
//
// THE PROBLEM THIS SOLVES
// set_lineup.js needs the address of the selection list, and that address is a
// heap allocation: it dies when fm.exe restarts, and it can even be freed and
// reused inside a single run (observed 2026-08-16 -- a squad-vector address
// recorded 17 hours earlier had become an unrelated structure while the process
// never restarted). Without a locator the whole write layer is one restart away
// from being useless.
//
// HOW IT ANCHORS
// Player UIDs and names are GAME data, not process data -- they are identical
// across restarts. So a persisted roster (data/roster/*.json) is a stable anchor
// even though every address in the process has changed. For each roster player we
// build the exact byte signature of their record:
//
//     u32 UID | u32 length of first name | first name bytes
//
// which is long enough to be effectively unique, and scan for it. Then, around
// each hit, we find the LONGEST valid chain of records -- that chain is the list,
// and its start is the base, regardless of which player we happened to anchor on.
//
//   node scripts/manager/locate_lineup.js
//   node scripts/manager/locate_lineup.js --roster data/roster/aston-villa.json --json

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const DUMP_MANY = path.join(REPO, 'scripts', 'win', 'dump_many.ps1');
const TMP_DIR = path.join(REPO, 'data', 'snapshots');

const NAME_RE = /^[A-Za-zÀ-ÿ' .\-]+$/;
const MIN_CHAIN = 11;          // a real selection list is 11 starters + subs
const WINDOW_BACK = 0x900;     // how far before a hit the list might start
const WINDOW_FWD  = 0x1200;    // enough to cover XI + 9 subs

// -ExecutionPolicy Bypass: the machine blocks .ps1 files; this is a per-child
// override and changes no machine or user setting.
function ps(script, args) {
  return execFileSync(PS,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
}

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, ''));
}

function signatureOf(player) {
  const name = Buffer.from(player.first, 'utf8');
  const b = Buffer.alloc(8 + name.length);
  b.writeUInt32LE(player.uid, 0);
  b.writeUInt32LE(name.length, 4);
  name.copy(b, 8);
  return [...b].map(x => x.toString(16).padStart(2, '0').toUpperCase()).join(' ');
}

// One pass for EVERY anchor. Scanning per anchor meant up to 23 sequential
// sweeps of ~2.4 GB, which dominated the decision loop's wall clock; scan_mem.ps1
// takes many patterns at once and dispatches on first byte, so the whole roster
// costs about what one player used to.
function scanAll(players) {
  const patFile = path.join(TMP_DIR, 'locate_patterns.json');
  const out = path.join(TMP_DIR, 'locate_hits.json');
  fs.writeFileSync(patFile, JSON.stringify(
    players.map((p) => ({ label: String(p.uid), pattern: signatureOf(p) }))));
  ps(SCAN, ['-PatternFile', patFile, '-Out', out, '-Max', '60']);
  return readJson(out).byLabel || {};
}

// Dump every hit's window in ONE PowerShell call. Spawning a process per hit was
// the entire bottleneck -- hundreds of ~1s process starts -- not the reading.
function dumpWindows(starts, len) {
  const spec = path.join(TMP_DIR, 'locate_spec.json');
  const out = path.join(TMP_DIR, 'locate_windows.json');
  fs.writeFileSync(spec, JSON.stringify(
    starts.map((s, i) => ({ label: 'w' + i, addr: s.toString(16).toUpperCase() }))));
  ps(DUMP_MANY, ['-Spec', spec, '-Length', String(len), '-Out', out]);
  const raw = readJson(out);
  const byLabel = {};
  for (const r of raw.rows) {
    const arr = Array.isArray(r.bytes) ? r.bytes : (r.bytes && r.bytes.value) || [];
    byLabel[r.label] = Buffer.from(arr);
  }
  return starts.map((_, i) => byLabel['w' + i] || Buffer.alloc(0));
}

// Try to read ONE record at exactly `off`.
function recordAt(buf, off, uidSet) {
  if (off + 12 > buf.length) return null;
  const uid = buf.readUInt32LE(off);
  if (!uidSet.has(uid)) return null;
  const fLen = buf.readUInt32LE(off + 4);
  if (fLen < 2 || fLen > 24 || off + 8 + fLen > buf.length) return null;
  const first = buf.slice(off + 8, off + 8 + fLen).toString('utf8');
  if (!NAME_RE.test(first)) return null;
  const lOff = off + 8 + fLen;
  if (lOff + 4 > buf.length) return null;
  const lLen = buf.readUInt32LE(lOff);
  if (lLen < 2 || lLen > 28 || lOff + 4 + lLen > buf.length) return null;
  const last = buf.slice(lOff + 4, lOff + 4 + lLen).toString('utf8');
  if (!NAME_RE.test(last)) return null;
  return { uid, first, last, off, end: lOff + 4 + lLen };
}

// Records are NOT laid end to end -- each carries further fields after the names,
// so there is a gap before the next UID (~0x25 bytes in the sample decoded by
// hand). Requiring adjacency finds exactly one record and stops, which is what
// made the first version of this locator report nothing. Allow a bounded gap
// instead; bounded so unrelated records elsewhere cannot be chained together.
// Observed inter-record gap is 0x25. 0x60 was too loose -- it chained across a
// boundary into an adjacent list, producing a 25-entry "chain" with players
// repeated. Keep it just above the real gap.
const MAX_GAP = 0x30;

function chainAt(buf, off, uidSet) {
  const out = [];
  let o = off;
  for (;;) {
    const rec = recordAt(buf, o, uidSet);
    if (!rec) break;
    out.push(rec);
    let next = -1;
    for (let g = 0; g <= MAX_GAP; g++) {
      if (recordAt(buf, rec.end + g, uidSet)) { next = rec.end + g; break; }
    }
    if (next < 0) break;
    o = next;
  }
  return out;
}

function main() {
  const argv = process.argv.slice(2);
  const rosterPath = argv.includes('--roster')
    ? argv[argv.indexOf('--roster') + 1]
    : path.join(REPO, 'data', 'roster', 'aston-villa.json');
  const asJson = argv.includes('--json');

  const roster = readJson(rosterPath);
  const uidSet = new Set(roster.players.map(p => p.uid));
  if (!asJson) console.log('roster: ' + roster.club + ', ' + roster.players.length + ' players');

  // Try roster players in turn -- the anchor only has to be someone in the
  // matchday squad, and we cannot know in advance who that is.
  let best = null;
  const candidates = [];
  const showAll = argv.includes('--all');
  const byLabel = scanAll(roster.players);
  const totalHits = Object.values(byLabel).reduce((n, h) => n + h.length, 0);
  if (!asJson) console.log(`  ${totalHits} hit(s) across ${roster.players.length} anchors`);

  // Collect windows around every hit, deduped -- several anchors land in the same
  // list, and dumping the same window repeatedly is pure waste.
  const seen = new Set();
  const starts = [];
  for (const hits of Object.values(byLabel)) {
    for (const h of hits.slice(0, 8)) {
      const s = parseInt(h, 16) - WINDOW_BACK;
      const bucket = s >> 12;                    // one window per ~4 KB page
      if (seen.has(bucket)) continue;
      seen.add(bucket);
      starts.push(s);
    }
  }

  const bufs = dumpWindows(starts, WINDOW_BACK + WINDOW_FWD);
  bufs.forEach((buf, idx) => {
    // The anchor may be mid-list, so consider chains starting anywhere in the
    // window rather than assuming the hit is the start.
    for (let o = 0; o + 12 <= buf.length; o++) {
      const c = chainAt(buf, o, uidSet);
      if (c.length < MIN_CHAIN) continue;
      const base = starts[idx] + o;
      const uids = c.map(r => r.uid);
      const dup = uids.length !== new Set(uids).size;
      candidates.push({ base, records: c, dup });
    }
  });

  // Collapse suffix-chains: keep only the longest chain per distinct end address.
  const byEnd = new Map();
  for (const c of candidates) {
    const end = c.records[c.records.length - 1].uid + ':' + (c.base + c.records[c.records.length - 1].end);
    const prev = byEnd.get(end);
    if (!prev || c.records.length > prev.records.length) byEnd.set(end, c);
  }
  const distinct = [...byEnd.values()].sort((a, b) => b.records.length - a.records.length);

  if (showAll) {
    console.log('\ndistinct chains found: ' + distinct.length);
    distinct.slice(0, 20).forEach(c => {
      const uids = c.records.map(r => r.uid);
      const at = i => (c.records[i] ? c.records[i].last : '-');
      console.log('  base=0x' + c.base.toString(16).toUpperCase().padEnd(9) +
        ' n=' + String(c.records.length).padStart(2) +
        ' uniq=' + String(new Set(uids).size).padStart(2) +
        (c.dup ? ' DUP' : '   ') +
        '  GK=' + at(0).padEnd(10) + ' DL=' + at(4).padEnd(10) + ' STC=' + at(10));
    });
  }

  // Two filters, because "longest chain" and "majority" are both wrong on their own.
  //
  // 1. PLAUSIBILITY. Several 19-entry chains are not team sheets at all -- one
  //    family had Björn Engels (an injured centre-back, GK rating 1) in the GK
  //    slot. A real selection list starts with a goalkeeper. This family was also
  //    the most numerous, so a naive majority vote picks it.
  //
  // 2. STALENESS IS REAL AND MAJORITY DOES NOT SOLVE IT. FM keeps many copies and
  //    old generations survive. Measured live: 23 copies held the PRE-change XI
  //    (Taylor/Watkins) while only 21 held the current one (Targett/Davis, which
  //    is what the UI showed). So a count-based rule picks the stale answer.
  //    Liveness can only be established BEHAVIOURALLY -- the live copy is the one
  //    that changes when the lineup changes. set_lineup.js acts anyway, so it can
  //    resolve this for free by keeping whichever copy reflects its own change.
  //    Here we surface the disagreement instead of hiding it.
  const gkRating = {};
  for (const p of roster.players) gkRating[p.uid] = (p.pos && p.pos.GK) || 0;

  const plausible = distinct.filter(c => !c.dup && gkRating[c.records[0].uid] >= 10);

  const groups = new Map();
  for (const c of plausible) {
    const sig = c.records.slice(0, 11).map(r => r.uid).join(',');
    if (!groups.has(sig)) groups.set(sig, []);
    groups.get(sig).push(c);
  }
  const ranked = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);

  if (ranked.length && (showAll || ranked.length > 1)) {
    console.log('\nplausible XI variants (a goalkeeper in the GK slot):');
    ranked.forEach(([, cs], i) => {
      console.log('  [' + i + '] ' + String(cs.length).padStart(3) + ' copies  base=0x' +
        cs[0].base.toString(16).toUpperCase() + '  ' +
        cs[0].records.slice(0, 11).map(x => x.last).join(', '));
    });
  }

  if (ranked.length > 1) {
    console.log('\nWARNING: copies disagree, so which is LIVE cannot be determined by');
    console.log('reading alone -- stale generations survive and can outnumber the current');
    console.log('one (measured: 23 stale vs 21 live). Resolve behaviourally: apply a change');
    console.log('with set_lineup.js and keep whichever base reflects it. Reporting variant');
    console.log('[0] below, which is NOT guaranteed to be current.');
  }

  if (!best) best = ranked.length ? ranked[0][1][0] : (distinct.find(c => !c.dup) || distinct[0] || null);
  const ambiguous = ranked.length > 1;

  if (!best) {
    const msg = 'could not locate the selection list -- is a tactic set up with an XI picked?';
    if (asJson) console.log(JSON.stringify({ ok: false, error: msg }));
    else console.error(msg);
    process.exit(2);
  }

  const baseHex = best.base.toString(16).toUpperCase();
  if (asJson) {
    console.log(JSON.stringify({
      ok: true, base: baseHex, count: best.records.length,
      ambiguous,                                  // true => may be a stale copy
      variants: ranked.map(([, cs]) => ({
        base: cs[0].base.toString(16).toUpperCase(), copies: cs.length,
        xi: cs[0].records.slice(0, 11).map(r => r.last),
      })),
      players: best.records.map(r => ({ uid: r.uid, name: r.first + ' ' + r.last })),
    }));
  } else {
    console.log('\nselection list located at 0x' + baseHex + '  (' + best.records.length + ' entries)');
    const SLOTS = ['GK','DR','DCR','DCL','DL','DM','MCL','MCR','AMR','AML','STC'];
    best.records.forEach((r, i) => {
      const slot = i < SLOTS.length ? SLOTS[i] : 'S' + (i - SLOTS.length + 1);
      console.log('  ' + slot.padEnd(4) + ' ' + r.first + ' ' + r.last);
    });
    console.log('\nuse:  node scripts/manager/set_lineup.js --base ' + baseHex + ' ...');
  }
}

main();
