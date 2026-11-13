#!/usr/bin/env node
// Generic between-match event dispatch.
//
// Each handler in HANDLERS exposes:
//   TYPE                         event_type string
//   detect(readers)              -> null when inactive, else an event envelope
//   prompt(event, profile)       -> { eventType, systemPrompt, initialContext }; throws if !event.ready
//   resolveDecision(event, dec)  -> the concrete action, or throws with a model-readable error
//   liveReaders()                -> memory-only readers for the real game
//
// Envelope shape (shared by every handler):
//   { event_type, ready, blocked_reason, payload, actions, provenance }
// `payload` is the only part a model sees; `actions` holds UI geometry for the
// controller; `provenance` records how each field was obtained.
//
// Handlers are checked in order and the first active one wins: FM shows one
// required response at a time, so ordering only matters if stale state makes two
// look active, and then the earlier, more tightly gated handler is preferred.
//
// Press-conference questions are the first and so far only handler. Others
// (transfer offers, team selection, tactical meeting) slot in here as they gain
// memory-only readers. See TODO.md "Required-response/event dispatch".
//
//   node scripts/manager/between_match_events.js          # summary of the active event
//   node scripts/manager/between_match_events.js --json   # full envelope as one JSON line

const pressConference = require('./events/press_conference');

const HANDLERS = [pressConference];

function detectActive(handlers = HANDLERS, readersFor = h => h.liveReaders()) {
  for (const h of handlers) {
    const event = h.detect(readersFor(h));
    if (event) return { handler: h, event };
  }
  return null;
}

function handlerFor(eventType, handlers = HANDLERS) {
  const h = handlers.find(x => x.TYPE === eventType);
  if (!h) throw new Error(`no handler registered for ${eventType}`);
  return h;
}

module.exports = { HANDLERS, detectActive, handlerFor };

if (require.main === module) {
  try {
    const active = detectActive();
    const event = active ? active.event : null;
    if (process.argv.includes('--json')) console.log(JSON.stringify({ event }));
    else if (!event) console.log('between_match_events: no active event');
    else {
      console.log(`${event.event_type}: ${event.ready ? 'ready' : `BLOCKED (${event.blocked_reason})`}`);
      if (event.payload.question_text) console.log(`  question: ${event.payload.question_text}`);
      (event.payload.choices || []).forEach(c => console.log(`  ${c.index}: ${c.text}`));
    }
  } catch (e) {
    console.error(`between_match_events: ${e.message}`);
    process.exit(1);
  }
}
