// Between-match event: a press-conference question awaiting the manager's answer.
//
// First event registered in between_match_events.js. Every reader is injected,
// so the logic is testable without fm.exe; liveReaders() wires in the real
// memory-only scripts.
//
// Fail-closed rule (carried over from run_press_conference.js): if the question
// text cannot be read, the event is reported but NOT ready, and prompt() refuses.
// A model must never answer a press question it cannot see.

const path = require('path');
const { execFileSync } = require('child_process');

const TYPE = 'press_conference_question';

function lastJsonLine(text) {
  const line = String(text).trim().split(/\r?\n/).filter(x => x.trim().startsWith('{')).pop();
  if (!line) throw new Error('no JSON object in child output');
  return JSON.parse(line.replace(/^﻿/, ''));
}

// A reader that exits non-zero but still printed a JSON verdict (read_press_question
// exits 2 when it fails closed) should yield that verdict, not an exception.
function runJson(script, args = []) {
  try {
    return lastJsonLine(execFileSync(process.execPath, [script, ...args], { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 }));
  } catch (e) {
    if (e.stdout) {
      try { return lastJsonLine(e.stdout); } catch (_) { /* fall through */ }
    }
    throw e;
  }
}

function liveReaders(dir = path.resolve(__dirname, '..')) {
  return {
    pressState: () => runJson(path.join(dir, 'read_press_state.js'), ['--json']),
    pressChoices: () => runJson(path.join(dir, 'read_press_choices.js'), ['--json']),
    pressQuestion: () => runJson(path.join(dir, 'read_press_question.js'), ['--json']),
  };
}

// Returns null when no press question is active, else an event envelope.
function detect(readers) {
  const state = readers.pressState();
  // Same semantic gate as run_press_conference.js: stale response widgets survive
  // the final answer, so nothing else is read without a current question.
  if (!state || !state.current_question) return null;

  const choices = readers.pressChoices();
  if (!choices || !Array.isArray(choices.choices) || choices.choices.length < 2) {
    return envelope(state, null, [], 'no_response_choices');
  }
  let question;
  try { question = readers.pressQuestion(); }
  catch (e) { question = { ok: false, reason: `reader_error: ${e.message}` }; }

  const blocked = question && question.ok && question.text ? null : `question_text_unavailable: ${question?.reason || 'unknown'}`;
  return envelope(state, question, choices.choices, blocked);
}

function envelope(state, question, choices, blockedReason) {
  return {
    event_type: TYPE,
    ready: !blockedReason,
    blocked_reason: blockedReason,
    // What the model is allowed to see.
    payload: {
      question_text: question?.ok ? question.text : null,
      question_number: state.answered_count + 1,
      questions_known: state.question_count,
      choices: choices.map((c, i) => ({ index: i, text: c.text })),
    },
    // What the controller needs to act and audit. Never sent to the model.
    actions: choices.map((c, i) => ({ index: i, click: c.click })),
    provenance: {
      source: 'fm.exe memory',
      question_object: state.current_question.address,
      question_id: state.current_question.id,
      question_text_method: question?.method || null,
      question_text_verified_live: question?.verified_live ?? null,
    },
  };
}

function prompt(event, profile, { club = 'Aston Villa' } = {}) {
  if (event.event_type !== TYPE) throw new Error(`not a ${TYPE} event`);
  if (!event.ready) throw new Error(`press event not ready: ${event.blocked_reason}`);
  const p = event.payload;
  const systemPrompt = `You are managing ${club} in Football Manager 2021. Manager profile: ${profile.name}; ` +
    `risk tolerance ${profile.risk_tolerance}; tactical philosophy ${profile.tactical_philosophy}. ` +
    `Answer the journalist's question yourself by choosing one of the offered responses.`;
  const options = p.choices.map(c => `${c.index}: ${c.text}`).join('\n');
  const initialContext = `Press conference, question ${p.question_number}.\n` +
    `Question: ${p.question_text}\n\nResponses:\n${options}\n\n` +
    `Reply JSON only: {"index":0,"reasoning":"brief reason"}`;
  return { eventType: TYPE, systemPrompt, initialContext };
}

// Returns the action for a model decision, or throws with a message suitable for
// feeding back to the model on retry.
function resolveDecision(event, decision) {
  const idx = Number(decision?.index);
  if (!Number.isInteger(idx) || idx < 0 || idx >= event.actions.length) {
    throw new Error(`index must be an integer from 0 to ${event.actions.length - 1}, got ${JSON.stringify(decision?.index)}`);
  }
  return { index: idx, text: event.payload.choices[idx].text, click: event.actions[idx].click };
}

module.exports = { TYPE, detect, prompt, resolveDecision, liveReaders };
