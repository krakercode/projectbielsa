#!/usr/bin/env node
// Drive FM's top-right navigation until authoritative GAME time moves.
//
// This is deliberately a SMALL primitive, not a general inbox solver. Clicking
// the same top-right control walks through Inbox/Social Feed/Next Unread/Continue.
// If FM shows MUST RESPOND, those clicks do not answer it, so this times out and
// reports a blocker rather than making an unevaluated football/admin decision.
//
//   node scripts/manager/advance_until_progress.js
//   node scripts/manager/advance_until_progress.js --max-clicks 10 --json

const { execFileSync } = require('child_process');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const FOCUS = path.join(REPO, 'scripts', 'win', 'focus.ps1');
const CLICK = path.join(REPO, 'scripts', 'win', 'click.ps1');
const READ_TIME = path.join(REPO, 'scripts', 'win', 'read_game_time.ps1');

// Screenshot-frame coordinates. click.ps1 scales these to the real display.
const TOP_RIGHT = { x: 1400, y: 23 };

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const hasFlag = (f) => process.argv.includes(f);
function ps(script, args = []) {
  return execFileSync(PS,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
    { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
}

function readTime() {
  const raw = ps(READ_TIME, ['-AsJson']).trim();
  return JSON.parse(raw.split(/\r?\n/).filter(Boolean).pop());
}

function clickTopRight() {
  ps(CLICK, [
    '-X', String(TOP_RIGHT.x), '-Y', String(TOP_RIGHT.y),
    '-FromScreenshot', '-SettleMs', '70',
  ]);
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function emit(result, asJson) {
  if (asJson) console.log(JSON.stringify(result));
  else {
    console.log(`advance_until_progress: ${result.advanced ? 'advanced' : 'blocked/no progress'}`);
    console.log(`  before: ${result.before.fingerprint}`);
    console.log(`  after:  ${result.after.fingerprint}`);
    console.log(`  clicks: ${result.clicks}, elapsed: ${(result.elapsed_ms / 1000).toFixed(1)}s`);
  }
}
function main() {
  const maxClicks = Number(arg('--max-clicks', '40'));
  const intervalMs = Number(arg('--interval-ms', '450'));
  const timeoutMs = Number(arg('--timeout-ms', '45000'));
  const asJson = hasFlag('--json');

  ps(FOCUS, ['-ProcessName', 'fm']);
  const before = readTime();
  let after = before;
  let clicks = 0;
  const t0 = Date.now();

  while (clicks < maxClicks && Date.now() - t0 < timeoutMs) {
    clickTopRight();
    clicks++;
    sleep(intervalMs);
    after = readTime();
    if (after.fingerprint !== before.fingerprint) break;
  }

  const result = {
    advanced: after.fingerprint !== before.fingerprint,
    clicks,
    elapsed_ms: Date.now() - t0,
    before,
    after,
  };
  emit(result, asJson);
  process.exitCode = result.advanced ? 0 : 2;
}

try { main(); }
catch (e) {
  console.error(`advance_until_progress: ${e.message}`);
  process.exit(1);
}
