// Turns the raw Cheat Engine squad dump into the state a manager model sees.
//
// This is where cheat/human mode plugs in, exactly as docs/control-interface.md
// specifies: the write side is identical in both modes, only reads are filtered.
//
// Two jobs beyond filtering:
//
// 1. SCALE CONVERSION. dump_state.lua deliberately emits FM's internal values.
//    Attributes are 1-100 internally and displayed as 1-20 (displayed =
//    round(internal / 5)). A model shown "Dribbling 85" would reason about it as
//    an off-the-charts number. Convert here, at the presentation boundary, and
//    leave the dump raw.
//
// 2. COMPACTION. data/snapshots/squad.json is ~43KB for 23 players. That is
//    12-15k tokens before any prompt scaffolding, which does not fit sensibly in
//    an 8B's usable context. get_squad() therefore returns a compact summary and
//    get_player() returns the deep dive -- which is what the design doc's "open
//    questions" section already predicted would be necessary.

const fs = require('fs');

const ATTR_GROUPS = ['Technical', 'Mental', 'Physical', 'Goalkeeping'];
const HIDDEN_GROUP = 'Hidden';

/** internal 1-100 -> displayed 1-20 */
function toDisplay(v) {
  if (typeof v !== 'number') return null;
  return Math.round(v / 5);
}

function positionsOf(p) {
  const pos = p.Positions || {};
  // Position ratings are 1-20; 15+ is "can play there" territory in FM terms.
  return Object.entries(pos)
    .filter(([, v]) => typeof v === 'number' && v >= 15)
    .sort((a, b) => b[1] - a[1])
    .map(([k]) => k);
}

function nameOf(p) {
  const n = (p['Player Info'] || {})['Name (Read Only)'] || {};
  const first = n['First Name'] || '';
  const last = n['Last Name'] || '';
  // Full Name is a lazily-populated cache in FM and is often absent -- see
  // docs/phase1-notes.md. First+Last are reliable.
  return `${first} ${last}`.trim() || '(unknown)';
}

/**
 * Compact per-player summary. Deliberately small: name, position, condition,
 * and an ability signal. Everything else needs an explicit get_player().
 */
function summarise(p, idx, mode) {
  const info = p['Player Info'] || {};
  const other = p.Other || {};
  const attrs = p.Attributes || {};

  const row = {
    id: idx,
    name: nameOf(p),
    positions: positionsOf(p),
    age_year_of_birth: info['Birth Year'] ?? null,
    // Condition/fitness are 0-10000 internally.
    condition_pct: typeof other.Condition === 'number' ? Math.round(other.Condition / 100) : null,
    fitness_pct: typeof other.Fitness === 'number' ? Math.round(other.Fitness / 100) : null,
  };

  if (mode === 'cheat') {
    row.ca = attrs.CA ?? null;
    row.pa = attrs.PA ?? null;
  } else {
    // HUMAN MODE -- placeholder, and flagged as such.
    //
    // Phase 5's real question (read FM's own "known to user" flags vs
    // reimplementing the masking) is NOT answered here. This bucket is a
    // stand-in so the pipeline can be exercised end to end. It must NOT be
    // used for any published result: a coarse bucket of true CA still leaks
    // ordering information a human manager would not reliably have.
    row.ability_estimate = caBucket(attrs.CA);
    row.masking = 'placeholder-not-phase5';
  }
  return row;
}

function caBucket(ca) {
  if (typeof ca !== 'number') return null;
  if (ca >= 150) return 'world class';
  if (ca >= 135) return 'very good';
  if (ca >= 120) return 'solid';
  if (ca >= 100) return 'squad player';
  return 'fringe';
}

/** Full detail for one player, for get_player(). */
function detail(p, idx, mode) {
  const out = summarise(p, idx, mode);
  const attrs = p.Attributes || {};
  out.attributes = {};
  for (const g of ATTR_GROUPS) {
    if (!attrs[g]) continue;
    out.attributes[g] = Object.fromEntries(
      Object.entries(attrs[g]).map(([k, v]) => [k, toDisplay(v)])
    );
  }
  out.preferred_foot = {
    left: toDisplay(attrs['Left Foot']),
    right: toDisplay(attrs['Right Foot']),
  };
  if (mode === 'cheat') {
    if (attrs[HIDDEN_GROUP]) {
      out.hidden_attributes = Object.fromEntries(
        Object.entries(attrs[HIDDEN_GROUP]).map(([k, v]) => [k, toDisplay(v)])
      );
    }
    out.personality = p.Personality || null;
  }
  const c = p.Contract || {};
  out.contract = {
    wage_per_week: c['Wage Per Week (£)'] ?? null,
    expires_year: c['Expires Year'] ?? null,
  };
  return out;
}

function uidOf(p) {
  return (((p || {})['_'] || {})['Dont touch'] || {}).UID;
}

/**
 * Load a squad snapshot (from scripts/manager/read_squad.js, or the older
 * scripts/lua/dump_squad.lua output -- same shape).
 *
 * @param {string} path
 * @param {"cheat"|"human"} mode
 * @param {{availableUids?: Set<number>}} [opts]
 *
 * AVAILABILITY MATTERS. A squad read returns every REGISTERED player -- 23 for
 * Villa -- but only those fit and eligible can actually be picked; the matchday
 * list was 19, with four injured or unavailable. Without filtering, a selector
 * happily picks an injured player and the write layer then fails with "not in the
 * matchday squad". Pass the UIDs FM currently offers (from locate_lineup.js) and
 * the rest are dropped before anyone gets to choose them.
 *
 * Note ids are indices into the FILTERED list, so they stay contiguous and match
 * what the model is shown.
 */
function loadSquad(path, mode = 'cheat', opts = {}) {
  const raw = JSON.parse(fs.readFileSync(path, 'utf8'));
  let players = raw.players || [];
  const all = players.length;
  if (opts.availableUids && opts.availableUids.size) {
    players = players.filter((p) => opts.availableUids.has(uidOf(p)));
  }
  return {
    source: path,
    mode,
    squad_array: raw.squad_array,
    squad_count: raw.squad_count,
    registered_count: all,
    available_count: players.length,
    players,
    summary: players.map((p, i) => summarise(p, i, mode)),
    detailFor: (id) => (players[id] ? detail(players[id], id, mode) : null),
  };
}

module.exports = { loadSquad, summarise, detail, toDisplay, caBucket, uidOf };
