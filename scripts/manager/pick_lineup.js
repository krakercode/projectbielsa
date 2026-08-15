#!/usr/bin/env node
//
// The pick_lineup decision event, end to end, against a real squad snapshot.
//
//   node scripts/manager/pick_lineup.js [--mode cheat|human] [--model qwen3:8b]
//                                       [--snapshot data/snapshots/squad.json]
//                                       [--strategy oneshot|tools] [--dry-run]
//
// This is the first executable slice of the eval and it deliberately needs NO
// write layer: it reads a real squad dump, asks a model for a starting XI, and
// validates and logs the answer. Nothing is written back to the game.
//
// Why this matters now: it exercises the whole model-facing half of the pipeline
// -- state compaction, mode filtering, prompt scaffold, structured output,
// parsing, validation, decision logging -- while Phase 2 does not exist. Any
// problem in that half shows up here rather than after the write layer lands.

const fs = require('fs');
const path = require('path');
const { OllamaProvider } = require('./provider');
const { loadSquad } = require('./squad_state');

const REPO = path.resolve(__dirname, '..', '..');

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const hasFlag = (f) => process.argv.includes(f);

// ---------------------------------------------------------------- prompt scaffold
// Kept here while there is exactly one event type. Extract to prompts.js when a
// second event lands, per docs/control-interface.md's shared-scaffold design.

function renderProfile(p) {
  return [
    `Manager profile: ${p.name}`,
    `Risk tolerance: ${p.risk_tolerance}`,
    `Tactical philosophy: ${p.tactical_philosophy}`,
    `Rotation policy: ${p.squad_building.rotation_policy}`,
    `Trust in youth: ${p.squad_building.youth_trust}`,
  ].join('\n');
}

function systemPrompt(profile, mode) {
  const modeNote =
    mode === 'cheat'
      ? 'You can see true current ability (CA) and potential ability (PA) for every player. These are exact.'
      : 'You CANNOT see true ability values. You get coarse estimates only, as a real manager would. Reason under uncertainty and say when you are unsure.';

  return `You are managing a football club in Football Manager 2021.

${renderProfile(profile)}

Information mode: ${mode.toUpperCase()}
${modeNote}

House rules:
- Pick exactly 11 players.
- Every player must be one of the players given to you, referenced by their numeric "id".
- A valid XI needs exactly one goalkeeper.
- Respect the positions listed for each player. Do not invent positions for them.
- Condition is a percentage. Starting a player below 80% risks injury and poor performance.

Reply with ONLY a JSON object, no prose outside it, in exactly this shape:
{
  "formation": "4-2-3-1",
  "starting_xi": [ { "id": 0, "position": "GK" } ],
  "captain_id": 0,
  "reasoning": "one or two sentences"
}`;
}

function userPrompt(squad) {
  return `Here is your available squad (${squad.summary.length} players).

${JSON.stringify(squad.summary, null, 1)}

Pick the strongest available starting XI for the next fixture.`;
}

// ---------------------------------------------------------------- validation
// The design doc requires write tools to validate before touching the game and
// to return a correctable error rather than crashing or silently no-opping. The
// same validation is worth running on a read-only proposal, because it tells us
// how often a given model produces a *usable* answer -- which is a headline
// number for the eval, not an implementation detail.

function validate(decision, squad) {
  const errors = [];
  if (!decision) return ['no decision object parsed from the model reply'];

  const xi = decision.starting_xi;
  if (!Array.isArray(xi)) {
    errors.push('starting_xi missing or not an array');
    return errors;
  }
  if (xi.length !== 11) errors.push(`starting_xi has ${xi.length} players, expected 11`);

  const valid = new Set(squad.summary.map((p) => p.id));
  const seen = new Set();
  let keepers = 0;

  for (const slot of xi) {
    const id = slot && slot.id;
    if (!valid.has(id)) {
      errors.push(`player id ${JSON.stringify(id)} is not in the squad`);
      continue;
    }
    if (seen.has(id)) errors.push(`player id ${id} selected more than once`);
    seen.add(id);
    if (String(slot.position || '').toUpperCase() === 'GK') keepers++;
  }
  if (keepers !== 1) errors.push(`XI names ${keepers} goalkeepers, expected exactly 1`);

  if (decision.captain_id !== undefined && !seen.has(decision.captain_id)) {
    errors.push(`captain_id ${decision.captain_id} is not in the starting XI`);
  }
  return errors;
}

function describe(decision, squad) {
  if (!decision || !Array.isArray(decision.starting_xi)) return '(nothing to show)';
  const byId = new Map(squad.summary.map((p) => [p.id, p]));
  return decision.starting_xi
    .map((s) => {
      const p = byId.get(s.id);
      return `  ${String(s.position || '?').padEnd(4)} ${p ? p.name : '??? id=' + s.id}`;
    })
    .join('\n');
}

// ---------------------------------------------------------------- main

async function main() {
  const mode = arg('--mode', 'cheat');
  const model = arg('--model', 'qwen3:8b');
  const snapshot = path.resolve(REPO, arg('--snapshot', 'data/snapshots/squad.json'));
  const strategy = arg('--strategy', 'oneshot');
  const profilePath = path.resolve(__dirname, 'profiles', arg('--profile', 'pragmatic') + '.json');

  if (!fs.existsSync(snapshot)) {
    console.error(`No squad snapshot at ${snapshot}`);
    console.error('Produce one from the CE Lua Engine:');
    console.error('  dofile([[<repo>\\scripts\\lua\\locate_vector.lua]]) locate_vector()');
    console.error('  dump_squad_to_file(nil, "<header>")');
    process.exit(1);
  }

  const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
  const squad = loadSquad(snapshot, mode);
  const provider = new OllamaProvider({ model });

  console.log(`pick_lineup  model=${provider.name}  mode=${mode}  strategy=${strategy}`);
  console.log(`squad: ${squad.summary.length} players from ${path.relative(REPO, snapshot)}`);

  try {
    await provider.health();
  } catch (e) {
    console.error(`Ollama not reachable: ${e.message}`);
    console.error('Start it with: ollama serve');
    process.exit(1);
  }

  // Load the model first so the measured wall clock is inference, not the ~5GB
  // VRAM load. Otherwise the first run of a session looks far slower than it is.
  process.stdout.write('warming model... ');
  const warmT0 = Date.now();
  await provider.warm();
  console.log(`${((Date.now() - warmT0) / 1000).toFixed(1)}s`);

  const sys = systemPrompt(profile, mode);
  const usr = userPrompt(squad);
  if (hasFlag('--dry-run')) {
    console.log('\n--- system ---\n' + sys + '\n--- user ---\n' + usr);
    console.log(`\n(approx ${Math.round((sys.length + usr.length) / 4)} tokens of prompt)`);
    return;
  }

  const t0 = Date.now();
  const result = await provider.decide({
    eventType: 'pick_lineup',
    systemPrompt: sys,
    initialContext: usr,
    strategy,
  });

  const errors = validate(result.decision, squad);
  console.log(`\nwall clock: ${(Date.now() - t0) / 1000}s   tokens in/out: ${result.tokens.input}/${result.tokens.output}`);
  if (result.error) console.log(`provider error: ${result.error}`);
  console.log(`formation: ${result.decision?.formation ?? '(none given)'}`);
  console.log(describe(result.decision, squad));
  console.log(`reasoning: ${result.decision?.reasoning ?? '(none)'}`);
  console.log(errors.length ? `\nVALIDATION FAILED:\n  - ${errors.join('\n  - ')}` : '\nvalidation: OK');

  // Decision log -- JSON Lines under data/logs/, per docs/control-interface.md.
  const logDir = path.join(REPO, 'data', 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  const entry = {
    event_type: 'pick_lineup',
    logged_at: new Date().toISOString(),
    save_snapshot: path.relative(REPO, snapshot),
    mode,
    manager_profile: profile.name,
    model: provider.name,
    strategy,
    decision: result.decision,
    validation_errors: errors,
    reasoning_raw: result.reasoning,
    tokens: result.tokens,
    wall_clock_ms: result.wallClockMs,
    provider_error: result.error,
  };
  fs.appendFileSync(path.join(logDir, 'decisions.jsonl'), JSON.stringify(entry) + '\n');
  console.log(`logged -> data/logs/decisions.jsonl`);

  process.exitCode = errors.length ? 2 : 0;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
