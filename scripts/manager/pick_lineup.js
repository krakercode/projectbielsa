#!/usr/bin/env node
//
// The pick_lineup decision event: ask a model to fill the tactic's eleven slots.
//
//   node scripts/manager/pick_lineup.js [--mode cheat|human] [--model qwen3:8b]
//                                       [--snapshot data/snapshots/squad_live.json]
//                                       [--strategy oneshot|tools|baseline] [--dry-run]
//
// Read-only: this produces and validates a decision, it does not apply it.
// run_decision.js is what closes the loop by applying the result.
//
// SLOT-BASED, as of 2026-08-16. It used to return {id, position} using FM's
// position vocabulary, but the write layer fills the tactic's SLOTS, and mapping
// one onto the other requires a guess that can silently misplace players. See the
// note at the top of prompts.js.

const fs = require('fs');
const path = require('path');
const { OllamaProvider } = require('./provider');
const { loadSquad } = require('./squad_state');
const prompts = require('./prompts');
const tactic = require('./tactic');

const REPO = path.resolve(__dirname, '..', '..');

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const hasFlag = (f) => process.argv.includes(f);

// ---------------------------------------------------------------- validation
//
// Hard errors are things that make the team illegal or unusable. Playing an
// outfielder out of position is NOT one of them -- a manager may legitimately do
// that and it is a poor choice rather than an invalid one, so it is reported as a
// warning. An outfielder in goal is a broken team, so that IS an error.

function validate(decision, squad) {
  const errors = [];
  const warnings = [];
  if (!decision) return { errors: ['no decision object parsed from the model reply'], warnings };

  const sel = decision.selection;
  if (!sel || typeof sel !== 'object' || Array.isArray(sel)) {
    return { errors: ['"selection" missing or not an object of slot -> player id'], warnings };
  }

  const known = new Set(squad.summary.map((p) => p.id));
  const used = new Map();

  for (const slot of tactic.DATA_ORDER) {
    if (!(slot in sel)) { errors.push(`slot ${slot} not filled`); continue; }
    const id = sel[slot];
    if (!known.has(id)) { errors.push(`slot ${slot}: player id ${JSON.stringify(id)} is not in the squad`); continue; }
    if (used.has(id)) errors.push(`player id ${id} used in both ${used.get(id)} and ${slot}`);
    used.set(id, slot);

    const raw = squad.players[id] || {};
    const rating = tactic.ratingForSlot(raw.Positions || {}, slot);
    if (slot === 'GK') {
      if (rating < tactic.PLAYABLE) {
        errors.push(`slot GK: ${squad.summary[id].name} is not a goalkeeper (GK rating ${rating})`);
      }
    } else if (rating < tactic.PLAYABLE) {
      warnings.push(`${squad.summary[id].name} is out of position at ${slot} (rating ${rating})`);
    } else if (rating < tactic.NATURAL) {
      warnings.push(`${squad.summary[id].name} is not natural at ${slot} (rating ${rating})`);
    }
  }

  for (const slot of Object.keys(sel)) {
    if (!tactic.DATA_ORDER.includes(slot)) errors.push(`unknown slot "${slot}"`);
  }

  if (decision.captain_id !== undefined && !used.has(decision.captain_id)) {
    errors.push(`captain_id ${decision.captain_id} is not in the selected eleven`);
  }
  return { errors, warnings };
}

function describe(decision, squad) {
  if (!decision || !decision.selection) return '(nothing to show)';
  return tactic.DATA_ORDER.map((slot) => {
    const id = decision.selection[slot];
    const p = squad.summary[id];
    return `  ${slot.padEnd(4)} ${p ? p.name : '??? id=' + id}`;
  }).join('\n');
}

// ---------------------------------------------------------------- baseline
//
// Deterministic best-XI-by-CA, no model involved. Two reasons it lives here:
// it exercises the whole loop without model variance, so a failure is provably
// plumbing rather than the model; and PLAN.md names it as the honest bar --
// "if the LLM can't beat best-XI-by-CA, that is the headline finding".

function baselineSelection(squad) {
  const taken = new Set();
  const selection = {};
  const score = (p) => (typeof p.ca === 'number' ? p.ca : 0);

  // Fill the most constrained slots first, otherwise a scarce specialist (the
  // only fit goalkeeper) can be consumed by a slot that had alternatives.
  const order = [...tactic.DATA_ORDER].sort(
    (a, b) => candidates(a).length - candidates(b).length
  );

  function candidates(slot, bar = tactic.PLAYABLE) {
    return squad.summary.filter((p) => {
      if (taken.has(p.id)) return false;
      const raw = squad.players[p.id] || {};
      return tactic.ratingForSlot(raw.Positions || {}, slot) >= bar;
    });
  }

  for (const slot of order) {
    // Prefer NATURAL fits, and only drop to merely playable if there are none.
    // Without this the greedy pass hands right-back to a high-CA centre-back and
    // leaves the actual right-back on the bench -- which makes the baseline
    // weaker than a naive human would be, and a bar that is too low is useless.
    let use = candidates(slot, tactic.NATURAL);
    if (!use.length) use = candidates(slot, tactic.PLAYABLE);
    // Last resort: any remaining player. A team of ten is not a valid comparison
    // point, so fill the slot and let the validator flag it as out of position.
    if (!use.length) use = squad.summary.filter((p) => !taken.has(p.id));
    if (!use.length) continue;
    use.sort((a, b) => score(b) - score(a));
    selection[slot] = use[0].id;
    taken.add(use[0].id);
  }

  const capt = tactic.DATA_ORDER.map((s) => selection[s]).filter((v) => v !== undefined)
    .sort((a, b) => score(squad.summary[b]) - score(squad.summary[a]))[0];

  return { selection, captain_id: capt, reasoning: 'baseline: highest CA available per slot, no model' };
}

// ---------------------------------------------------------------- reusable entry
/**
 * Produce a validated lineup decision. Shared by this CLI and run_decision.js.
 * @returns {{decision, errors, warnings, result}}
 */
async function decideLineup({ squad, profile, mode, model, strategy, provider, maxAttempts = 3 }) {
  if (strategy === 'baseline') {
    const decision = baselineSelection(squad);
    const { errors, warnings } = validate(decision, squad);
    return {
      decision, errors, warnings,
      result: {
        eventType: 'pick_lineup', model: 'baseline:highest-ca', strategy: 'baseline',
        decision, reasoning: decision.reasoning, tokens: { input: 0, output: 0 },
        wallClockMs: 0, error: null, toolCalls: [],
      },
    };
  }

  const p = provider || new OllamaProvider({ model });
  const sys = prompts.pickLineupSystem(profile, mode);
  const base = prompts.pickLineupUser(squad);

  // Give the model its validation errors back and let it correct itself, which is
  // what docs/control-interface.md specifies ("the model sees the error and can
  // self-correct within the same loop"). The tools strategy gets this for free;
  // oneshot needs it explicitly, and an 8B needs it often -- the first live run
  // put the same player in two slots.
  //
  // Attempts are recorded so "usable answer on the first try" stays measurable.
  // That rate is a headline number for the eval, not an implementation detail, so
  // retries must never be able to hide it.
  let result = null, errors = [], warnings = [], attempts = 0;
  for (attempts = 1; attempts <= (maxAttempts || 1); attempts++) {
    const context = attempts === 1 ? base
      : `${base}\n\nYour previous answer was rejected:\n- ${errors.join('\n- ')}\n` +
        `Return a corrected JSON object filling every slot exactly once.`;
    result = await p.decide({ eventType: 'pick_lineup', systemPrompt: sys, initialContext: context, strategy });
    ({ errors, warnings } = validate(result.decision, squad));
    if (!errors.length) break;
  }
  result.attempts = attempts;
  return { decision: result.decision, errors, warnings, result };
}

// ---------------------------------------------------------------- main

async function main() {
  const mode = arg('--mode', 'cheat');
  const model = arg('--model', 'qwen3:8b');
  const strategy = arg('--strategy', 'oneshot');
  const profilePath = path.resolve(__dirname, 'profiles', arg('--profile', 'pragmatic') + '.json');

  // Prefer the live read; fall back to the older hand-made dump if present.
  let snapshot = path.resolve(REPO, arg('--snapshot', 'data/snapshots/squad_live.json'));
  if (!fs.existsSync(snapshot)) {
    const legacy = path.join(REPO, 'data', 'snapshots', 'squad.json');
    if (fs.existsSync(legacy)) snapshot = legacy;
  }
  if (!fs.existsSync(snapshot)) {
    console.error(`No squad snapshot at ${snapshot}`);
    console.error('Produce one live with:  node scripts/manager/read_squad.js');
    process.exit(1);
  }

  const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
  const squad = loadSquad(snapshot, mode);

  console.log(`pick_lineup  mode=${mode}  strategy=${strategy}  tactic=${tactic.NAME}`);
  console.log(`squad: ${squad.summary.length} players from ${path.relative(REPO, snapshot)}`);

  let provider = null;
  if (strategy !== 'baseline') {
    provider = new OllamaProvider({ model });
    try {
      await provider.health();
    } catch (e) {
      console.error(`Ollama not reachable: ${e.message}\nStart it with: ollama serve`);
      process.exit(1);
    }
    if (hasFlag('--dry-run')) {
      console.log('\n--- system ---\n' + prompts.pickLineupSystem(profile, mode));
      console.log('\n--- user ---\n' + prompts.pickLineupUser(squad));
      return;
    }
    // Load the model first so measured wall clock is inference, not the ~5GB load.
    process.stdout.write('warming model... ');
    const w0 = Date.now();
    await provider.warm();
    console.log(`${((Date.now() - w0) / 1000).toFixed(1)}s`);
  }

  const t0 = Date.now();
  const { decision, errors, warnings, result } = await decideLineup({
    squad, profile, mode, model, strategy, provider,
  });

  console.log(`\nwall clock: ${(Date.now() - t0) / 1000}s   tokens in/out: ${result.tokens.input}/${result.tokens.output}`);
  if (result.error) console.log(`provider error: ${result.error}`);
  console.log(describe(decision, squad));
  console.log(`reasoning: ${decision?.reasoning ?? '(none)'}`);
  if (warnings.length) console.log(`\nwarnings:\n  - ${warnings.join('\n  - ')}`);
  console.log(errors.length ? `\nVALIDATION FAILED:\n  - ${errors.join('\n  - ')}` : '\nvalidation: OK');

  const logDir = path.join(REPO, 'data', 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  fs.appendFileSync(path.join(logDir, 'decisions.jsonl'), JSON.stringify({
    event_type: 'pick_lineup',
    logged_at: new Date().toISOString(),
    save_snapshot: path.relative(REPO, snapshot),
    tactic: tactic.NAME,
    mode,
    manager_profile: profile.name,
    model: result.model,
    strategy,
    decision,
    validation_errors: errors,
    validation_warnings: warnings,
    reasoning_raw: result.reasoning,
    tokens: result.tokens,
    wall_clock_ms: result.wallClockMs,
    provider_error: result.error,
    applied: false,
  }) + '\n');
  console.log('logged -> data/logs/decisions.jsonl');

  process.exitCode = errors.length ? 2 : 0;
}

module.exports = { decideLineup, validate, describe, baselineSelection };

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
