#!/usr/bin/env node
// Read the formatted text of the CURRENT press-conference question from fm.exe memory.
//
// Observation is memory-only, like every other reader here: no screenshots, no OCR.
//
// STATUS (2026-11-13): written without live access, NOT yet verified in a press
// conference. The seam that holds the question text is still undecoded, so this
// reader discovers it: it walks a bounded pointer graph out of objects that should
// own or display the question, and asks press_question.js for a single
// question-like string that is not one of the live answers. It fails closed
// (exit 2) on zero or several candidates and prints them with their offset paths.
//
// Once a live run has shown the real path, add it to PINNED_PATHS below. Pinned
// paths are tried first and the walk becomes a fallback/diagnostic.
//
//   node scripts/manager/read_press_question.js            # human-readable
//   node scripts/manager/read_press_question.js --json     # one JSON line
//   node scripts/manager/read_press_question.js --discover # list every candidate, never fails on ambiguity
//
// Refuses to run unless read_press_state.js reports a current question: stale UI
// generations survive in memory after the final answer (see the 2026-09-09 log).

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { selectQuestion, rejectReason, extractStrings, normalise, validPtr } = require('./press_question');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const RTTI = path.join(REPO, 'scripts', 'win', 'rtti_index.js');
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const DUMP = path.join(REPO, 'scripts', 'win', 'dump_many.ps1');
const STATE = path.join(__dirname, 'read_press_state.js');
const CHOICES = path.join(__dirname, 'read_press_choices.js');
const TMP = path.join(REPO, 'data', 'snapshots');

const DEPTH = 3;
const BYTES_PER_NODE = 768;
const MAX_NODES = 2500;
const MAX_INSTANCES_PER_CLASS = 8;

// Classes whose live instances are walked as roots, besides the current
// PRESS_CONFERENCE_QUESTION. Matched as substrings of the mangled RTTI name;
// only primary vtables (object_offset 0) are used.
const ROOT_CLASS_PATTERNS = [
  'INTERACTION_GROUPED_RESPONSE_SELECTOR_PANEL',
  'PRESS_CONFERENCE_PANEL',
  'INTERACTION_PRESS_CONFERENCE',
  'INTERACTION_QUESTION',
];

// Filled in from a live --discover run. Format: { root, offsets:[...], stringOffset }
// e.g. { root:'question', offsets:[0x48, 0x10], stringOffset:4 } means
// read qword at question+0x48, then qword at that+0x10, text starts 4 bytes in.
const PINNED_PATHS = [];

const hasFlag = f => process.argv.includes(f);
function run(cmd, args) { return execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 }); }
function ps(script, args) { return run(PS, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args]); }
function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, '')); }
function writeJson(p, v) { fs.writeFileSync(p, JSON.stringify(v, null, 2)); }
function bytes(row) { return Buffer.from(row.bytes.value || row.bytes); }
function hex(v) { return '0x' + BigInt(v).toString(16).toUpperCase(); }
function bare(v) { return BigInt(v).toString(16).toUpperCase(); }
function lastJsonLine(text) {
  const line = text.trim().split(/\r?\n/).filter(x => x.trim().startsWith('{')).pop();
  if (!line) throw new Error('no JSON object in child output');
  return JSON.parse(line.replace(/^﻿/, ''));
}
function pattern(v) {
  const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v));
  return [...b].map(x => x.toString(16).padStart(2, '0').toUpperCase()).join(' ');
}

function dumpMany(addrs, length, tag) {
  if (!addrs.length) return [];
  const spec = path.join(TMP, `press-question-${tag}-spec.json`);
  const out = path.join(TMP, `press-question-${tag}-dump.json`);
  writeJson(spec, addrs.map((a, i) => ({ label: `n${i}`, addr: bare(a) })));
  ps(DUMP, ['-Spec', spec, '-Length', String(length), '-Out', out]);
  return readJson(out).rows.map(r => (r.ok ? bytes(r) : null));
}

function findRoots() {
  const roots = [];
  const index = JSON.parse(run(process.execPath, [RTTI, '--contains', 'INTERACTION']));
  const press = JSON.parse(run(process.execPath, [RTTI, '--contains', 'PRESS_CONFERENCE']));
  const rows = [...index.rows, ...press.rows].filter(r =>
    r.object_offset === 0 && ROOT_CLASS_PATTERNS.some(p => r.name.includes(p)));
  const unique = [...new Map(rows.map(r => [r.vtable, r])).values()];
  if (!unique.length) return roots;
  const patFile = path.join(TMP, 'press-question-root-patterns.json');
  const hitFile = path.join(TMP, 'press-question-root-hits.json');
  writeJson(patFile, unique.map((r, i) => ({ label: `c${i}`, pattern: pattern(r.vtable) })));
  ps(SCAN, ['-PatternFile', patFile, '-Out', hitFile, '-Max', String(MAX_INSTANCES_PER_CLASS)]);
  const hits = readJson(hitFile).byLabel || {};
  unique.forEach((r, i) => (hits[`c${i}`] || []).forEach(addr => roots.push({
    root: r.name.replace(/^\.\?AV/, '').replace(/@@$/, ''),
    address: BigInt('0x' + addr),
  })));
  return roots;
}

// Breadth-first, one dump_many call per depth level so a walk costs DEPTH+1
// PowerShell start-ups rather than one per node.
function walk(roots) {
  const nodes = [];
  const seen = new Set();
  let frontier = roots.map(r => ({ root: r.root, path: r.root, address: r.address }));
  for (let depth = 0; depth <= DEPTH && frontier.length && nodes.length < MAX_NODES; depth++) {
    frontier = frontier.filter(n => {
      if (seen.has(n.address)) return false;
      seen.add(n.address);
      return true;
    }).slice(0, MAX_NODES - nodes.length);
    const bufs = dumpMany(frontier.map(n => n.address), BYTES_PER_NODE, `d${depth}`);
    const next = [];
    frontier.forEach((n, i) => {
      const b = bufs[i];
      if (!b) return;
      nodes.push({ ...n, address: hex(n.address), bytes: b });
      if (depth === DEPTH) return;
      for (let off = 0; off + 8 <= b.length; off += 8) {
        const v = b.readBigUInt64LE(off);
        if (validPtr(v) && !seen.has(v)) next.push({ root: n.root, path: `${n.path}+0x${off.toString(16).toUpperCase()}`, address: v });
      }
    });
    frontier = next;
  }
  return nodes;
}

function readPinned(roots, pinned) {
  const results = [];
  for (const pin of pinned) {
    const root = roots.find(r => r.root === pin.root);
    if (!root) continue;
    let addr = root.address;
    let ok = true;
    for (const off of pin.offsets) {
      const [b] = dumpMany([addr + BigInt(off)], 8, 'pin');
      if (!b) { ok = false; break; }
      addr = b.readBigUInt64LE(0);
      if (!validPtr(addr)) { ok = false; break; }
    }
    if (!ok) continue;
    const [b] = dumpMany([addr + BigInt(pin.stringOffset || 0)], 1024, 'pintext');
    if (!b) continue;
    const s = extractStrings(b, 1).find(x => x.offset === 0);
    if (!s) continue;
    const text = normalise(s.text);
    if (!rejectReason(text)) results.push({ text, pin });
  }
  return results;
}

function main() {
  fs.mkdirSync(TMP, { recursive: true });
  const discover = hasFlag('--discover');
  const state = lastJsonLine(run(process.execPath, [STATE, '--json']));
  if (!state.current_question) {
    const result = { ok: false, reason: 'no_current_question', source: 'fm.exe memory', state_phase: state.phase };
    emit(result);
    process.exit(2);
  }
  const choices = lastJsonLine(run(process.execPath, [CHOICES, '--json']));
  const responseTexts = choices.choices.map(c => c.text);

  const roots = [{ root: 'question', address: BigInt(state.current_question.address) }, ...findRoots()];

  if (!discover && PINNED_PATHS.length) {
    const pinned = readPinned(roots, PINNED_PATHS);
    const distinct = [...new Set(pinned.map(p => p.text))];
    if (distinct.length === 1) {
      emit({ ok: true, source: 'fm.exe memory', method: 'pinned', text: distinct[0],
        question: state.current_question, answered_count: state.answered_count, pins: pinned.map(p => p.pin) });
      return;
    }
  }

  const nodes = walk(roots);
  const sel = selectQuestion(nodes, responseTexts, { preferRoot: 'question' });
  const result = {
    ...sel,
    source: 'fm.exe memory',
    verified_live: false,
    question: state.current_question,
    answered_count: state.answered_count,
    roots: roots.map(r => ({ root: r.root, address: hex(r.address) })),
    nodes_walked: nodes.length,
  };
  emit(result);
  if (!sel.ok && !discover) process.exit(2);
}

function emit(result) {
  if (hasFlag('--json')) { console.log(JSON.stringify(result)); return; }
  if (result.ok) {
    console.log(`question (${result.method}): ${result.text}`);
    (result.provenance || []).forEach(p => console.log(`  at ${p.path} (${p.address})`));
  } else {
    console.log(`read_press_question: no single question text (${result.reason})`);
  }
  if (hasFlag('--discover') || !result.ok) {
    (result.candidates || []).forEach((c, i) => {
      console.log(`candidate ${i}: ${c.text}`);
      c.sightings.slice(0, 5).forEach(s => console.log(`    ${s.path} (${s.address})`));
    });
  }
}

try { main(); }
catch (e) { console.error(`read_press_question: ${e.message}`); process.exit(1); }
