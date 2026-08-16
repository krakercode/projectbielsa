#!/usr/bin/env node
//
// THE LOOP: read the live game -> ask for a decision -> apply it -> verify it
// against the game -> log everything.
//
// This is PLAN.md's Phase 4 exit criterion: "one full loop -- state -> decision
// -> action -- runs end to end for a between-match event, without manual
// intervention."
//
//   node scripts/manager/run_decision.js --dry-run            decide + log, do NOT act
//   node scripts/manager/run_decision.js --strategy baseline  no model, deterministic
//   node scripts/manager/run_decision.js --mode cheat         full loop with the model
//
// PRECONDITION, discovered the hard way: the selection list is a TRANSIENT RENDER
// BUFFER. In a freshly launched fm.exe it does not exist at all until the Tactics
// screen has been drawn, and locate_lineup finds nothing. So this navigates to
// Tactics first unless --no-nav is given.
//
// Nothing here writes to memory. The action goes through set_lineup.js, which
// drives FM's UI -- see scripts/lua/actions.lua for why the write layer is
// UI-driven by construction rather than by developer discipline.

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { loadSquad } = require('./squad_state');
const { decideLineup, describe } = require('./pick_lineup');
const { OllamaProvider } = require('./provider');
const tactic = require('./tactic');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const FOCUS = path.join(REPO, 'scripts', 'win', 'focus.ps1');
const CLICK = path.join(REPO, 'scripts', 'win', 'click.ps1');
const READ_SQUAD = path.join(__dirname, 'read_squad.js');
const SET_LINEUP = path.join(__dirname, 'set_lineup.js');

const TACTICS_SIDEBAR = { x: 47, y: 132 };   // screenshot-frame coords

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const hasFlag = (f) => process.argv.includes(f);

function ps(script, args) {
  return execFileSync(PS,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
}
function node(script, args) {
  return execFileSync(process.execPath, [script, ...args],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
}

function ensureTacticsScreen() {
  ps(FOCUS, ['-ProcessName', 'fm']);
  ps(CLICK, ['-X', String(TACTICS_SIDEBAR.x), '-Y', String(TACTICS_SIDEBAR.y), '-FromScreenshot']);
  // give FM time to draw, which is what materialises the selection list
  execFileSync(PS, ['-NoProfile', '-Command', 'Start-Sleep -Seconds 5']);
}

async function main() {
  const mode = arg('--mode', 'cheat');
  const model = arg('--model', 'qwen3:8b');
  const strategy = arg('--strategy', 'oneshot');
  const profilePath = path.resolve(__dirname, 'profiles', arg('--profile', 'pragmatic') + '.json');
  const dryRun = hasFlag('--dry-run');
  const t0 = Date.now();

  console.log(`run_decision  mode=${mode}  strategy=${strategy}  tactic=${tactic.NAME}` +
              (dryRun ? '  [DRY RUN]' : ''));

  // 1. Make sure the tactics UI has been drawn, or there is no selection list.
  if (!hasFlag('--no-nav')) {
    console.log('\n[1] opening the Tactics screen');
    ensureTacticsScreen();
  }

  // 2. Live state, straight out of the game.
  console.log('[2] reading the live squad');
  const snapshot = path.join(REPO, 'data', 'snapshots', 'squad_live.json');
  const readOut = node(READ_SQUAD, ['--out', snapshot]);
  console.log('    ' + (readOut.trim().split(/\r?\n/).find((l) => l.includes('validated')) || '').trim());

  // 2b. Availability. A squad read returns every REGISTERED player, but only
  // those FM currently offers can be picked -- Villa has 23 registered and 19
  // available, the rest injured or unavailable. The live selection list is
  // exactly that offered set, so use it as the availability filter. Without this
  // a selector cheerfully picks an injured player and the write layer then
  // refuses it.
  let availableUids = null;
  try {
    const out = node(path.join(__dirname, 'locate_lineup.js'), ['--json']);
    const line = out.trim().split(/\r?\n/).filter((l) => l.startsWith('{')).pop();
    const j = JSON.parse(line);
    if (j.ok && j.players) availableUids = new Set(j.players.map((p) => p.uid));
  } catch (e) {
    console.log('    ! could not read the selection list; proceeding without an availability filter');
  }

  const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
  const squad = loadSquad(snapshot, mode, availableUids ? { availableUids } : {});
  console.log(`    ${squad.available_count}/${squad.registered_count} available` +
              (availableUids ? '' : ' (unfiltered)'));

  // 3. Decide.
  console.log(`[3] asking for a decision (${strategy})`);
  let provider = null;
  if (strategy !== 'baseline') {
    provider = new OllamaProvider({ model });
    try { await provider.health(); }
    catch (e) { console.error(`Ollama not reachable: ${e.message}\nStart it with: ollama serve`); process.exit(1); }
    await provider.warm();
  }
  const { decision, errors, warnings, result } = await decideLineup({
    squad, profile, mode, model, strategy, provider,
  });

  console.log(describe(decision, squad));
  if (decision?.reasoning) console.log(`    reasoning: ${decision.reasoning}`);
  if (warnings.length) console.log('    warnings: ' + warnings.join('; '));

  // 4. Refuse to act on an invalid decision. This is the point of validating.
  if (errors.length) {
    console.error('\nVALIDATION FAILED -- not applying:\n  - ' + errors.join('\n  - '));
    logDecision({ mode, strategy, profile, decision, errors, warnings, result,
                  applied: false, verified: null, snapshot, t0 });
    process.exit(2);
  }
  console.log('    validation: OK');

  if (dryRun) {
    console.log('\n[4] --dry-run: decision logged, nothing applied');
    logDecision({ mode, strategy, profile, decision, errors, warnings, result,
                  applied: false, verified: null, snapshot, t0 });
    return;
  }

  // 5. Translate slot -> squad index into slot -> player UID, which is what the
  //    write layer keys on (UIDs are game data and survive restarts; indices are
  //    just positions in this particular dump).
  const pairs = tactic.DATA_ORDER.map((slot) => {
    const p = squad.players[decision.selection[slot]] || {};
    const uid = ((p['_'] || {})['Dont touch'] || {}).UID;
    return `${slot}=${uid}`;
  });

  // 6. Apply through the UI-driven write layer, which verifies itself.
  console.log('\n[4] applying via set_lineup');
  let applyOut = '';
  let verified = false;
  try {
    applyOut = node(SET_LINEUP, ['--set', pairs.join(',')]);
    verified = /set_lineup: verified/.test(applyOut);
  } catch (e) {
    applyOut = (e.stdout || '') + (e.stderr || '');
    verified = false;
  }
  for (const line of applyOut.trim().split(/\r?\n/)) console.log('    ' + line);

  logDecision({ mode, strategy, profile, decision, errors, warnings, result,
                applied: true, verified, applyOut, snapshot, t0 });

  console.log(verified
    ? `\nrun_decision: LOOP COMPLETE (${((Date.now() - t0) / 1000).toFixed(1)}s)`
    : '\nrun_decision: APPLIED BUT NOT VERIFIED -- see output above');
  process.exitCode = verified ? 0 : 3;
}

// One line per decision, plus a copy of the exact state the model saw. PLAN.md
// asks for snapshots at every decision point so runs can be replayed across
// models on matched seeds -- cheap now, expensive to retrofit.
function logDecision({ mode, strategy, profile, decision, errors, warnings, result,
                       applied, verified, applyOut, snapshot, t0 }) {
  const logDir = path.join(REPO, 'data', 'logs');
  const stateDir = path.join(REPO, 'data', 'logs', 'states');
  fs.mkdirSync(stateDir, { recursive: true });

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const stateFile = path.join(stateDir, `state-${stamp}.json`);
  try { fs.copyFileSync(snapshot, stateFile); } catch {}

  fs.appendFileSync(path.join(logDir, 'decisions.jsonl'), JSON.stringify({
    event_type: 'pick_lineup',
    logged_at: new Date().toISOString(),
    loop: 'run_decision',
    tactic: tactic.NAME,
    mode,
    manager_profile: profile.name,
    model: result.model,
    strategy,
    // How many tries it took to produce a VALID decision. "usable on the first
    // attempt" is a headline eval number, so retries must not be able to hide it.
    attempts: result.attempts || 1,
    state_snapshot: path.relative(REPO, stateFile),
    decision,
    validation_errors: errors,
    validation_warnings: warnings,
    reasoning_raw: result.reasoning,
    tokens: result.tokens,
    decide_ms: result.wallClockMs,
    total_ms: Date.now() - t0,
    applied,
    verified,
    apply_output: applyOut || null,
    provider_error: result.error,
  }) + '\n');
  console.log(`    logged -> data/logs/decisions.jsonl (state: ${path.relative(REPO, stateFile)})`);
}

main().catch((e) => { console.error(e); process.exit(1); });
