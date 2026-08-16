// Phase 2 write layer: apply a starting XI to FM by driving its UI, then verify
// the result by re-reading the selection out of memory.
//
// WHY UI SIMULATION RATHER THAN A MEMORY WRITE
// Decided 2026-08-16 (see docs/session-log/2026-08-16-phase2-lineup-read.md):
//   * PLAN.md requires the write layer to be UI-equivalent as a STRUCTURAL
//     property -- "not developer discipline ... one violation invalidates a run".
//     A drag on the tactics screen cannot violate that; a memory poke relies on us
//     never making a mistake.
//   * Changing a lineup triggers validation, role/duty assignment and tactical
//     familiarity. Writing a UID into a slot risks a state the engine never agreed
//     to -- a correctness problem, not only a fairness one.
//   * The authoritative selection store is not located anyway. Four hypotheses
//     were ruled out; the eleven readable copies are UI models.
//
// WHY DRAG AND DROP RATHER THAN THE SWAP DROPDOWN
// The dropdown's candidate ORDER is not stable -- the same player appeared 2nd in
// one opening and 4th in another -- so clicking a row by index cannot be made
// reliable. Dragging has fixed endpoints at both ends: a known list row to a known
// list row. Verified live: dragging S5 onto the DL row swapped them correctly.
//
//   node scripts/manager/set_lineup.js --base DF9B0611 --dry-run
//   node scripts/manager/set_lineup.js --base DF9B0611 --set DL=29009633,STC=28107730
//
// --base is the address of the selection list. It is a heap address and dies with
// the process; re-derive it by scanning for a known starter's UID and finding the
// cluster (scripts/lua/scan_ptr.lua -> scan_u32, then look for the run of entries).

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const READ_MEM = path.join(REPO, 'scripts', 'win', 'read_mem.ps1');
const CLICK = path.join(REPO, 'scripts', 'win', 'click.ps1');
const FOCUS = path.join(REPO, 'scripts', 'win', 'focus.ps1');
const TMP = path.join(REPO, 'data', 'snapshots', 'set_lineup_state.json');

// Order the selection list is serialised in. NOTE this is NOT the order the rows
// appear on screen: the UI shows MCR above MCL, the data has MCL first. Rows are
// therefore mapped by NAME, never by shared index.
const DATA_ORDER = ['GK','DR','DCR','DCL','DL','DM','MCL','MCR','AMR','AML','STC'];

// Top-to-bottom order of the rows in the tactics right-hand panel.
const UI_ROW_ORDER = ['GK','DR','DCR','DCL','DL','DM','MCR','MCL','AMR','AML','STC',
                      'S1','S2','S3','S4','S5','S6','S7','S8','S9'];

// Row geometry in the agent-screenshot frame (1456x819). click.ps1 -FromScreenshot
// converts to real pixels, so the conversion lives in exactly one place.
const ROW0_Y = 160;
const ROW_DY = 28.85;
const ROW_X  = 1000;

function rowY(slot) {
  const i = UI_ROW_ORDER.indexOf(slot);
  if (i < 0) throw new Error('unknown slot ' + slot);
  return Math.round(ROW0_Y + ROW_DY * i);
}

// -ExecutionPolicy Bypass is needed because the machine's policy blocks running
// .ps1 files. It is a per-invocation override for this child process only -- it
// does not change any machine or user setting.
function ps(script, args) {
  return execFileSync(PS,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
    { encoding: 'utf8' });
}

function readSelection(base) {
  ps(READ_MEM, ['-ProcessName', 'fm', '-Address', base, '-Length', '2048', '-AsJson', TMP]);
  const raw = JSON.parse(fs.readFileSync(TMP, 'utf8').replace(/^﻿/, ''));
  const arr = Array.isArray(raw.bytes) ? raw.bytes : raw.bytes.value;
  const buf = Buffer.from(arr);
  return parseEntries(buf);
}

// Same record layout as scripts/manager/read_lineup.js:
//   u32 UID | u32 len | first name | u32 len | last name
// Strings are LENGTH-PREFIXED, not zero-terminated.
function parseEntries(buf) {
  const NAME_RE = /^[A-Za-zÀ-ÿ' .\-]+$/;
  const out = [];
  let o = 0;
  while (o + 12 <= buf.length) {
    const uid = buf.readUInt32LE(o);
    if (uid < 1_000_000 || uid > 99_999_999) { o++; continue; }
    const fLen = buf.readUInt32LE(o + 4);
    if (fLen < 2 || fLen > 24) { o++; continue; }
    const first = buf.slice(o + 8, o + 8 + fLen).toString('utf8');
    if (!NAME_RE.test(first)) { o++; continue; }
    const lLenOff = o + 8 + fLen;
    if (lLenOff + 4 > buf.length) { o++; continue; }
    const lLen = buf.readUInt32LE(lLenOff);
    if (lLen < 2 || lLen > 28) { o++; continue; }
    const last = buf.slice(lLenOff + 4, lLenOff + 4 + lLen).toString('utf8');
    if (!NAME_RE.test(last)) { o++; continue; }
    out.push({ uid, first, last });
    o = lLenOff + 4 + lLen;
  }
  return out.map((e, i) => ({
    ...e,
    slot: i < DATA_ORDER.length ? DATA_ORDER[i] : 'S' + (i - DATA_ORDER.length + 1),
  }));
}

function slotOfUid(entries, uid) {
  const e = entries.find(x => x.uid === uid);
  return e ? e.slot : null;
}

function drag(fromSlot, toSlot) {
  ps(CLICK, ['-X', String(ROW_X), '-Y', String(rowY(fromSlot)),
             '-ToX', String(ROW_X), '-ToY', String(rowY(toSlot)),
             '-Drag', '-FromScreenshot']);
}

function parseArgs(argv) {
  const out = { base: null, set: {}, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--base') out.base = argv[++i];
    else if (argv[i] === '--dry-run') out.dryRun = true;
    else if (argv[i] === '--set') {
      for (const pair of argv[++i].split(',')) {
        const [slot, uid] = pair.split('=');
        out.set[slot.trim()] = parseInt(uid, 10);
      }
    }
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.base) {
    console.error('usage: set_lineup.js --base <hexAddr> [--set DL=29009633,...] [--dry-run]');
    process.exit(1);
  }

  let entries = readSelection(args.base);
  if (entries.length < 11) {
    console.error('only ' + entries.length + ' entries parsed at ' + args.base +
                  ' -- wrong base, or the list moved. Re-derive it.');
    process.exit(2);
  }

  console.log('current selection:');
  entries.slice(0, 11).forEach(e => console.log('  ' + e.slot.padEnd(4) + ' ' + e.first + ' ' + e.last));

  const wanted = Object.entries(args.set);
  if (!wanted.length) { console.log('\nno --set given, nothing to do'); return; }

  // Work out the drags. Each is "put player U into slot S"; because a drag SWAPS
  // the two rows, the displaced player lands where U came from, which is exactly
  // what a human swap does too.
  const plan = [];
  for (const [slot, uid] of wanted) {
    const from = slotOfUid(entries, uid);
    if (!from) { console.error('player uid ' + uid + ' is not in the matchday squad'); process.exit(3); }
    if (from === slot) continue;                       // already there
    plan.push({ uid, from, to: slot });
  }

  if (!plan.length) { console.log('\nalready matches the requested XI'); return; }

  console.log('\nplanned drags:');
  plan.forEach(p => console.log('  ' + p.from + ' -> ' + p.to + '  (uid ' + p.uid + ')'));
  if (args.dryRun) { console.log('\n--dry-run, nothing applied'); return; }

  ps(FOCUS, ['-ProcessId', String(fmPid())]);
  for (const p of plan) {
    // re-read between drags: an earlier swap may have moved this player's row
    entries = readSelection(args.base);
    const from = slotOfUid(entries, p.uid);
    if (!from) { console.error('lost track of uid ' + p.uid); process.exit(4); }
    if (from === p.to) continue;
    console.log('  dragging ' + from + ' -> ' + p.to);
    drag(from, p.to);
  }

  // Verify against what the game actually did, not against what we intended.
  entries = readSelection(args.base);
  console.log('\nresulting selection:');
  entries.slice(0, 11).forEach(e => console.log('  ' + e.slot.padEnd(4) + ' ' + e.first + ' ' + e.last));

  let ok = true;
  for (const [slot, uid] of wanted) {
    const got = entries.find(e => e.slot === slot);
    const good = got && got.uid === uid;
    if (!good) ok = false;
    console.log('  ' + (good ? 'OK  ' : 'FAIL') + ' ' + slot + ' expected uid ' + uid +
                ', got ' + (got ? got.uid + ' (' + got.last + ')' : 'nothing'));
  }
  console.log(ok ? '\nset_lineup: verified' : '\nset_lineup: VERIFICATION FAILED');
  process.exit(ok ? 0 : 5);
}

function fmPid() {
  const out = execFileSync(PS, ['-NoProfile', '-Command',
    '(Get-Process -Name fm -ErrorAction SilentlyContinue | Select-Object -First 1).Id'],
    { encoding: 'utf8' }).trim();
  if (!out) { console.error('fm.exe is not running'); process.exit(1); }
  return parseInt(out, 10);
}

main();
