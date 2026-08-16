// Prompt scaffolds, one per decision event.
//
// Extracted from pick_lineup.js now that a second consumer exists
// (run_decision.js), which is the point docs/control-interface.md specifies for
// pulling the shared scaffold out.
//
// THE IMPORTANT CHANGE HERE: pick_lineup is now SLOT-BASED.
//
// It used to ask for `{id, position}` using FM's position vocabulary (GK, DC,
// MC...). But the write layer fills the active tactic's SLOTS (GK, DR, DCR, DCL,
// DL, DM, MCL, MCR, AMR, AML, STC). Those are not the same thing -- a 4-3-3 has
// two DC-capable slots and two MC-capable slots -- so anything mapping one to the
// other has to guess, and a wrong guess silently puts players in the wrong place.
//
// Asking the model to fill the tactic's actual slots removes the guess entirely,
// and is also more faithful to the game: a human fills the slots their tactic
// defines. Changing the shape of the team is a different action (set_tactic).

const tactic = require('./tactic');

function renderProfile(p) {
  return [
    `Manager profile: ${p.name}`,
    `Risk tolerance: ${p.risk_tolerance}`,
    `Tactical philosophy: ${p.tactical_philosophy}`,
    `Rotation policy: ${p.squad_building.rotation_policy}`,
    `Trust in youth: ${p.squad_building.youth_trust}`,
  ].join('\n');
}

function modeNote(mode) {
  return mode === 'cheat'
    ? 'You can see true current ability (CA) and potential ability (PA) for every player. These are exact.'
    : 'You CANNOT see true ability values. You get coarse estimates only, as a real manager would. Reason under uncertainty and say when you are unsure.';
}

function pickLineupSystem(profile, mode) {
  const slots = tactic.DATA_ORDER;
  return `You are managing a football club in Football Manager 2021.

${renderProfile(profile)}

Information mode: ${mode.toUpperCase()}
${modeNote(mode)}

Your tactic is ${tactic.NAME}. It has exactly these eleven slots, and you must
fill every one of them:

${slots.map((s) => '  - ' + tactic.describeSlot(s)).join('\n')}

House rules:
- Assign exactly one player to each of the eleven slots.
- Use each player at most once.
- Reference players by the numeric "id" given in the squad list.
- The GK slot must be a goalkeeper.
- The bracketed positions after each slot are what that slot wants. Playing
  someone out of position is allowed but weakens them, so do it deliberately.
- Condition is a percentage. Starting a player below 80% risks injury and poor
  performance.

Reply with ONLY a JSON object, no prose outside it, in exactly this shape:
{
  "selection": { ${slots.map((s) => `"${s}": 0`).join(', ')} },
  "captain_id": 0,
  "reasoning": "one or two sentences"
}`;
}

function pickLineupUser(squad) {
  return `Here is your available squad (${squad.summary.length} players).

${JSON.stringify(squad.summary, null, 1)}

Pick the strongest available team for the next fixture, filling every slot.`;
}

module.exports = { pickLineupSystem, pickLineupUser, renderProfile, modeNote };
