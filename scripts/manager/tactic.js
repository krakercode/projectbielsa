// The active tactic: slot names, their order, their screen geometry, and which
// FM positions each slot wants.
//
// WHY THIS FILE EXISTS
// The slot order was duplicated across read_lineup.js, set_lineup.js and the
// prompt scaffold. That is exactly how a silent bug gets in, because the two
// orders are NOT the same:
//
//   serialised order (memory):  ... DM, MCL, MCR, AMR ...
//   screen order (tactics UI):  ... DM, MCR, MCL, AMR ...
//
// MCL and MCR are swapped between them. Anything that assumes one order for both
// silently swaps the two central midfielders. Single source of truth here.
//
// CURRENT LIMITATION, stated plainly: this describes ONE tactic -- Cautious
// 4-3-3 DM Wide, the one set up on the working save. The formation is not read
// from the game yet, so changing the tactic in FM requires updating this file.
// Reading it live belongs with set_tactic(), which does not exist.

// Order the selection list is serialised in, and therefore the order
// read_lineup.js / read_squad-driven parsers see records.
const DATA_ORDER = ['GK', 'DR', 'DCR', 'DCL', 'DL', 'DM', 'MCL', 'MCR', 'AMR', 'AML', 'STC'];

// Top-to-bottom order of the rows in the tactics screen's right-hand panel,
// including the bench. Used for clicking and dragging.
const UI_ROW_ORDER = [
  'GK', 'DR', 'DCR', 'DCL', 'DL', 'DM', 'MCR', 'MCL', 'AMR', 'AML', 'STC',
  'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9',
];

// Row geometry in the agent-screenshot frame (1456x819). click.ps1
// -FromScreenshot converts to real pixels, so that conversion lives in one place.
const ROW0_Y = 160;
const ROW_DY = 28.85;
const ROW_X = 1000;

function rowY(slot) {
  const i = UI_ROW_ORDER.indexOf(slot);
  if (i < 0) throw new Error('unknown slot: ' + slot);
  return Math.round(ROW0_Y + ROW_DY * i);
}

// Which FM position ratings suit each slot. Keys match the Positions block in a
// player record (GK, SW, DL, DC, DR, WBL, WBR, DM, ML, MC, MR, AML, AMC, AMR, ST).
const SLOT_POSITIONS = {
  GK:  ['GK'],
  DR:  ['DR', 'WBR'],
  DCR: ['DC'],
  DCL: ['DC'],
  DL:  ['DL', 'WBL'],
  // Kept strict on purpose. Letting MC satisfy the DM slot put an attacking
  // midfielder in the holding role and called it a natural fit. DM, MC and AMC
  // are distinct roles in FM and should not substitute for each other silently;
  // where a squad genuinely lacks a specialist, the selector falls back and the
  // validator reports it as out of position rather than hiding it.
  DM:  ['DM'],
  MCL: ['MC'],
  MCR: ['MC'],
  AMR: ['AMR', 'MR'],
  AML: ['AML', 'ML'],
  STC: ['ST'],
};

// FM position ratings are 1-20. squad_state.js treats 15+ as "can play there".
// A lower bar is used for validation because a manager may legitimately field a
// player out of position -- that is a poor choice, not an illegal one, so it is
// reported rather than rejected. The goalkeeper slot is the exception: an
// outfielder in goal is a broken team, not a bold selection.
const NATURAL = 15;
const PLAYABLE = 10;

/** Best position rating this player has for the given slot. */
function ratingForSlot(positions, slot) {
  const keys = SLOT_POSITIONS[slot] || [];
  let best = 0;
  for (const k of keys) {
    const v = positions && positions[k];
    if (typeof v === 'number' && v > best) best = v;
  }
  return best;
}

function describeSlot(slot) {
  return `${slot} (${(SLOT_POSITIONS[slot] || []).join('/')})`;
}

module.exports = {
  NAME: 'Cautious 4-3-3 DM Wide',
  DATA_ORDER,
  UI_ROW_ORDER,
  SLOT_POSITIONS,
  NATURAL,
  PLAYABLE,
  ROW_X,
  rowY,
  ratingForSlot,
  describeSlot,
};
