// node --test scripts/manager/test/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const { extractStrings, rejectReason, selectQuestion } = require('../press_question');

// Simulate FM's text handle: 4-byte header then NUL-terminated UTF-8.
function handle(text) {
  return Buffer.concat([Buffer.from([1, 0, 0, 0]), Buffer.from(text, 'utf8'), Buffer.from([0, 0, 0xff, 0x13])]);
}
const Q = 'How do you assess Emiliano Martínez\'s form going into the Leicester game?';
const RESPONSES = [
  'We need to continue to work hard and make sure we play to our full potential',
  'I am delighted with how he has performed so far this season',
];

test('extractStrings keeps accented names in one run and reports the handle offset', () => {
  const s = extractStrings(handle(Q));
  assert.equal(s.length, 1);
  assert.equal(s[0].offset, 4);
  assert.equal(s[0].text, Q);
});

test('rejectReason accepts a formatted question and rejects lookalikes', () => {
  assert.equal(rejectReason(Q), null);
  assert.equal(rejectReason(RESPONSES[0]), 'no_question_mark');
  assert.equal(rejectReason('How do you rate [%person#1] ahead of [%team#2]?'), 'template_tokens');
  assert.equal(rejectReason('PRESS_CONFERENCE_QUESTION_TEXT?'), 'no_spaces');
  assert.equal(rejectReason('Why?'), 'too_short');
});

test('selectQuestion returns the unique question with its path', () => {
  const nodes = [
    { root: 'question', path: 'question+0x40', address: '0x1000', bytes: handle(Q) },
    { root: 'PANEL', path: 'PANEL+0x10', address: '0x2000', bytes: handle(RESPONSES[0]) },
  ];
  const r = selectQuestion(nodes, RESPONSES, { preferRoot: 'question' });
  assert.equal(r.ok, true);
  assert.equal(r.text, Q);
  assert.equal(r.provenance[0].path, 'question+0x40@+0x4');
});

test('a response that happens to contain "?" is never returned as the question', () => {
  const tricky = 'Are you asking me whether we can win this? Yes, we can';
  const nodes = [{ root: 'PANEL', path: 'PANEL', address: '0x1', bytes: handle(tricky) }];
  const r = selectQuestion(nodes, [tricky]);
  assert.equal(r.ok, false);
  assert.equal(r.reason, 'no_candidate');
});

test('two questions fail closed unless exactly one is under the question object', () => {
  const stale = 'What did you make of the result against Leeds on Monday night?';
  const ambiguous = [
    { root: 'PANEL', path: 'PANEL+0x8', address: '0x1', bytes: handle(stale) },
    { root: 'PANEL', path: 'PANEL+0x18', address: '0x2', bytes: handle(Q) },
  ];
  const r1 = selectQuestion(ambiguous, RESPONSES, { preferRoot: 'question' });
  assert.equal(r1.ok, false);
  assert.equal(r1.reason, 'ambiguous');
  assert.equal(r1.candidates.length, 2);

  const tied = [...ambiguous, { root: 'question', path: 'question+0x20', address: '0x3', bytes: handle(Q) }];
  const r2 = selectQuestion(tied, RESPONSES, { preferRoot: 'question' });
  assert.equal(r2.ok, true);
  assert.equal(r2.text, Q);
  assert.equal(r2.method, 'unique_under_question');
});
