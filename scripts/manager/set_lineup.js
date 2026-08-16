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
//   node scripts/manager/set_lineup.js --dry-run
//   node scripts/manager/set_lineup.js --set DL=29009633,STC=28107730
//   node scripts/manager/set_lineup.js --base DF9B0611 --set ...   # skip the lookup
//
// --base is optional. The selection list is a heap allocation: it dies when
// fm.exe restarts, and can even be freed and reused mid-run. So by default the
// address is located fresh via locate_lineup.js, which anchors on player UIDs and
// names -- game data that is stable across restarts, unlike any address. Pass
// --base only to skip that lookup when you already know the address.

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

const LOCATE = path.join(REPO, 'scripts', 'manager', 'locate_lineup.js');

// Every candidate copy of the selection list, most-copied first.
function getVariants() {
  const out = execFileSync(process.execPath, [LOCATE, '--json'],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const line = out.trim().split(/\r?\n/).filter(l => l.startsWith('{')).pop();
  const j = JSON.parse(line);
  if (!j.ok) throw new Error(j.error || 'locate failed');
  return j.variants && j.variants.length
    ? j.variants.map(v => v.base)
    : [j.base];
}

const xiSig = entries => entries ? entries.slice(0, 11).map(e => e.uid).join(',') : null;

// The roster is the sanity check on every read. These buffers are transient
// render allocations: one was freed and REUSED to hold Leicester's squad between
// a drag and the verification read, which parsed perfectly and reported a
// completely wrong XI. Any parse containing a player who is not ours means the
// buffer is no longer our selection list.
const ROSTER = (() => {
  const p = path.join(REPO, 'data', 'roster', 'aston-villa.json');
  const j = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, ''));
  return new Set(j.players.map(x => x.uid));
})();

// Returns null if the buffer is not (or is no longer) our selection list.
function readSelection(base) {
  ps(READ_MEM, ['-ProcessName', 'fm', '-Address', base, '-Length', '2048', '-AsJson', TMP]);
  const raw = JSON.parse(fs.readFileSync(TMP, 'utf8').replace(/^﻿/, ''));
  const arr = Array.isArray(raw.bytes) ? raw.bytes : raw.bytes.value;
  const entries = parseEntries(Buffer.from(arr));
  if (entries.length < 11) return null;
  if (entries.slice(0, 11).some(e => !ROSTER.has(e.uid))) return null;
  return entries;
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

  // With no --base, locate every candidate copy. Which one is live is settled
  // later, behaviourally, once we have made a change.
  let bases;
  if (args.base) {
    bases = [args.base];
  } else {
    console.log('locating the selection list...');
    bases = getVariants();
    console.log('  ' + bases.length + ' candidate cop' + (bases.length === 1 ? 'y' : 'ies') +
                ': ' + bases.map(b => '0x' + b).join(', '));
  }

  // Drop any base that no longer reads as OUR selection list.
  bases = bases.filter(b => readSelection(b) !== null);
  if (!bases.length) {
    console.error('no candidate base reads as an Aston Villa selection list ' +
                  '-- the buffers were recycled; re-run to locate again');
    process.exit(2);
  }

  let entries = readSelection(bases[0]);

  console.log('current selection:');
  entries.slice(0, 11).forEach(e => console.log('  ' + e.slot.padEnd(4) + ' ' + e.first + ' ' + e.last));

  const wanted = Object.entries(args.set);
  if (!wanted.length) { console.log('\nno --set given, nothing to do'); return; }

  // "Put player U into slot S". A drag SWAPS the two rows, so the displaced
  // player lands where U came from -- the same thing a human swap does.
  const planFrom = es => {
    if (!es) return null;
    const out = [];
    for (const [slot, uid] of wanted) {
      const from = slotOfUid(es, uid);
      if (!from) return null;                    // not in the matchday squad
      if (from === slot) continue;               // already there
      out.push({ uid, from, to: slot });
    }
    return out;
  };

  // Only trust "nothing to do" if EVERY copy agrees. A stale copy claiming the
  // target is already satisfied would otherwise make this a silent no-op -- which
  // is exactly what happened the first time this ran.
  const plans = bases.map(b => planFrom(readSelection(b))).filter(p => p !== null);
  if (!plans.length) {
    console.error('a requested player is not in the matchday squad, or every copy ' +
                  'was recycled mid-read');
    process.exit(3);
  }
  if (plans.every(p => p.length === 0)) {
    console.log('\nall ' + bases.length + ' copies agree: already matches the requested XI');
    return;
  }

  // Show the shortest outstanding plan -- i.e. the most up-to-date copy's view.
  const shortest = plans.filter(p => p.length).sort((a, b) => a.length - b.length)[0];
  console.log('\noutstanding changes (' + shortest.length + '):');
  shortest.forEach(p => console.log('  ' + p.from + ' -> ' + p.to + '  (uid ' + p.uid + ')'));
  if (args.dryRun) { console.log('\n--dry-run, nothing applied'); return; }

  ps(FOCUS, ['-ProcessId', String(fmPid())]);

  // LIVENESS, by "closest to target".
  //
  // Earlier attempts tried to identify one live copy and then track it. That does
  // not survive contact with reality: FM recycles these buffers constantly, and
  // after an action the live data can be in a buffer that did not exist when we
  // located. Both failure modes were observed -- a nine-drag plan silently
  // stopping after one drag, and every located copy going stale mid-run while the
  // game itself had changed correctly.
  //
  // The robust rule: every drag moves the team TOWARD the target, so among all
  // readable copies the live one is whichever has the FEWEST remaining
  // differences. Stale generations are by definition further behind. That needs
  // no calibration, self-corrects after any recycle, and cannot be fooled by
  // stale copies outnumbering live ones.
  // Locating from scratch costs a full memory scan, so the candidate list is
  // CACHED and merely re-read (cheap dumps) each iteration. A re-scan happens
  // only when the cached copies stop being usable -- either none is readable, or
  // none is making progress, which is the signal that FM has moved the live data
  // into a buffer allocated after we last looked.
  let cachedBases = args.base ? [args.base] : null;

  const evaluate = (list) => {
    let best = null;
    for (const b of list) {
      const es = readSelection(b);
      if (!es) continue;
      const p = planFrom(es);
      if (!p) continue;
      if (!best || p.length < best.plan.length) best = { base: b, entries: es, plan: p };
    }
    return best;
  };

  const bestLive = (force = false) => {
    if (!cachedBases || force) cachedBases = args.base ? [args.base] : getVariants();
    let best = evaluate(cachedBases);
    if (!best && !force && !args.base) {
      cachedBases = getVariants();
      best = evaluate(cachedBases);
    }
    return best;
  };

  let liveBase = null;
  let done = false;
  let lastRemaining = Infinity;
  for (let i = 0; i < 30; i++) {
    let cur = bestLive();
    // No progress since the last drag means our cached copies have all gone
    // stale -- the live data is somewhere we have not looked. Re-scan once.
    if (cur && cur.plan.length >= lastRemaining && !args.base) {
      const rescanned = bestLive(true);
      if (rescanned && rescanned.plan.length < cur.plan.length) cur = rescanned;
    }
    if (!cur) { console.error('  no readable copy of the selection list'); break; }
    liveBase = cur.base;
    if (!cur.plan.length) { done = true; break; }
    lastRemaining = cur.plan.length;
    const step = cur.plan[0];
    console.log(`  dragging ${step.from} -> ${step.to}  (${cur.plan.length} left, copy 0x${cur.base})`);
    drag(step.from, step.to);
  }
  if (!done) console.log('  (did not reach the target; verifying actual state)');
  if (!liveBase) { console.error('\ncould not read the selection list at all'); process.exit(6); }

  // Verify against what the game actually did, not against what we intended --
  // and re-resolve the live copy the same way, because the buffer can be recycled
  // between the last drag and this read.
  const final = bestLive();
  if (!final) {
    console.error('\ncannot locate a readable copy to verify against');
    process.exit(6);
  }
  liveBase = final.base;
  entries = final.entries;
  console.log('\nresulting selection (copy 0x' + liveBase + '):');
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
