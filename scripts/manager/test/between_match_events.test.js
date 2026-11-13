// node --test scripts/manager/test/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const press = require('../events/press_conference');
const { detectActive, handlerFor } = require('../between_match_events');

const STATE = {
  answered_count: 2, question_count: 8, phase: 'question',
  current_question: { address: '0xABC0', id: '0x51', journalist: '0x9' },
};
const CHOICES = { count: 3, choices: [
  { text: 'Answer A', click: { x: 340, y: 900 } },
  { text: 'Answer B', click: { x: 650, y: 900 } },
  { text: 'Answer C', click: { x: 960, y: 900 } },
] };
const QUESTION = { ok: true, text: 'Are you worried about Leicester\'s pace on the break?', method: 'unique', verified_live: false };
const PROFILE = { name: 'Pragmatic Pragmatist', risk_tolerance: 'medium', tactical_philosophy: 'compact' };

function readers(overrides = {}) {
  let choiceReads = 0;
  return {
    pressState: () => STATE,
    pressChoices: () => { choiceReads++; return CHOICES; },
    pressQuestion: () => QUESTION,
    get choiceReads() { return choiceReads; },
    ...overrides,
  };
}

test('no current question means no event and no widget reads', () => {
  const r = readers({ pressState: () => ({ ...STATE, current_question: null, phase: 'terminal_or_inactive' }) });
  assert.equal(press.detect(r), null);
  assert.equal(r.choiceReads, 0);
});

test('ready event keeps UI geometry out of the model payload', () => {
  const e = press.detect(readers());
  assert.equal(e.ready, true);
  assert.equal(e.payload.question_text, QUESTION.text);
  assert.equal(e.payload.question_number, 3);
  assert.deepEqual(e.payload.choices.map(c => c.text), ['Answer A', 'Answer B', 'Answer C']);
  assert.ok(!JSON.stringify(e.payload).includes('click'));
  const p = press.prompt(e, PROFILE);
  assert.match(p.initialContext, /Question: Are you worried/);
  assert.match(p.initialContext, /2: Answer C/);
});

test('missing question text blocks the event and prompt() refuses', () => {
  const e = press.detect(readers({ pressQuestion: () => ({ ok: false, reason: 'ambiguous' }) }));
  assert.equal(e.ready, false);
  assert.match(e.blocked_reason, /ambiguous/);
  assert.throws(() => press.prompt(e, PROFILE), /not ready/);
});

test('a throwing question reader blocks rather than crashes', () => {
  const e = press.detect(readers({ pressQuestion: () => { throw new Error('fm not running'); } }));
  assert.equal(e.ready, false);
  assert.match(e.blocked_reason, /reader_error: fm not running/);
});

test('resolveDecision maps an index to its click and rejects bad indices', () => {
  const e = press.detect(readers());
  assert.deepEqual(press.resolveDecision(e, { index: 1 }), { index: 1, text: 'Answer B', click: { x: 650, y: 900 } });
  assert.throws(() => press.resolveDecision(e, { index: 3 }), /0 to 2/);
  assert.throws(() => press.resolveDecision(e, { index: '1.5' }), /integer/);
});

test('dispatcher returns the first active handler and looks handlers up by type', () => {
  const idle = { TYPE: 'idle', detect: () => null };
  const active = detectActive([idle, press], () => readers());
  assert.equal(active.handler, press);
  assert.equal(active.event.event_type, 'press_conference_question');
  assert.equal(detectActive([idle], () => readers()), null);
  assert.equal(handlerFor('press_conference_question'), press);
  assert.throws(() => handlerFor('transfer_offer'), /no handler/);
});
