#!/usr/bin/env node
// Find live writable-memory instances of FM response classes.
//
// Static semantics come from scripts/win/rtti_index.js; live locations come from
// the existing read-only multi-pattern scanner. This does not inspect the screen.
//
//   node scripts/manager/find_responses.js
//   node scripts/manager/find_responses.js --json --out data/snapshots/responses.json

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const RTTI = path.join(REPO, 'scripts', 'win', 'rtti_index.js');
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const TMP_SPEC = path.join(REPO, 'data', 'snapshots', 'response-vtable-patterns.json');
const TMP_HITS = path.join(REPO, 'data', 'snapshots', 'response-vtable-hits.json');

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const hasFlag = (flag) => process.argv.includes(flag);
function vtablePattern(hex) {
  const b = Buffer.alloc(8);
  b.writeBigUInt64LE(BigInt(hex));
  return [...b].map((x) => x.toString(16).padStart(2, '0').toUpperCase()).join(' ');
}

function cleanName(name) {
  return name
    .replace(/^\.\?AV/, '')
    .replace(/@@$/, '')
    .replace(/[^A-Za-z0-9_?$@]/g, '_');
}

function main() {
  const index = JSON.parse(execFileSync(process.execPath,
    [RTTI, '--contains', 'RESPONSE'], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }));

  // CLASS_INFO_TEMPLATE objects are registration metadata, not response objects.
  // Keep other templated response types: some are genuine runtime wrappers.
  const rows = index.rows.filter((r) => !r.name.includes('CLASS_INFO_TEMPLATE'));
  const spec = rows.map((r, i) => ({
    label: `r${String(i).padStart(3, '0')}_${cleanName(r.name).slice(0, 90)}`,
    pattern: vtablePattern(r.vtable),
    name: r.name,
    vtable: r.vtable,
    vtable_rva: r.vtable_rva,
  }));
  fs.writeFileSync(TMP_SPEC, JSON.stringify(spec.map(({ label, pattern }) => ({ label, pattern })), null, 2));
  execFileSync(PS, [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCAN,
    '-PatternFile', TMP_SPEC, '-Out', TMP_HITS, '-Max', arg('--max', '64'),
  ], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });

  const hits = JSON.parse(fs.readFileSync(TMP_HITS, 'utf8').replace(/^\uFEFF/, ''));
  const active = [];
  for (const row of spec) {
    const addresses = (hits.byLabel || {})[row.label] || [];
    if (!addresses.length) continue;
    active.push({
      name: row.name,
      vtable: row.vtable,
      vtable_rva: row.vtable_rva,
      count: addresses.length,
      addresses,
    });
  }
  active.sort((a, b) => a.count - b.count || a.name.localeCompare(b.name));
  const result = {
    scanned_classes: spec.length,
    live_classes: active.length,
    live_instances: active.reduce((n, r) => n + r.count, 0),
    classes: active,
  };

  const out = arg('--out', '');
  if (out) fs.writeFileSync(path.resolve(out), JSON.stringify(result, null, 2) + '\n');
  if (hasFlag('--json')) console.log(JSON.stringify(result));
  else {
    console.log(`find_responses: ${result.live_instances} instance(s) across ${result.live_classes}/${result.scanned_classes} response classes`);
    for (const r of active) console.log(`${String(r.count).padStart(3)}  ${r.name}  ${r.addresses.join(', ')}`);
  }
}

try { main(); }
catch (e) { console.error(`find_responses: ${e.message}`); process.exit(1); }

