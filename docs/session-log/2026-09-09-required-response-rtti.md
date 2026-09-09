# Session Log — required-response RTTI dispatch

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 4 orchestration / Phase 3 prerequisite
- **Starting point:** authoritative GAME-time progress detection worked, but the loop could only stop at MUST RESPOND events; it could not identify or dispatch them from memory.
- **Access available this session:** live FM21 process, local Ollama (`qwen3:8b`), read-only process-memory tooling, synthetic UI input for actions.

## What did it do?

1. Continued the disposable live save from 5 October using `advance_until_progress.js`, with the GAME fingerprint as the independent progress signal.
2. Exercised the first real mandatory football decision chain: Watford's offer for Aaron Ramsey.
3. Qwen first chose to negotiate rather than accept/reject. The offer was changed to £200K upfront and submitted through FM's UI.
4. Watford returned a £250K non-negotiable counter. Qwen independently chose to accept it.
5. FM later produced the completion event and the transfer was confirmed, proving a sequential decision → action → later-response lifecycle.
6. Advanced the running save further, reaching at least 12 Oct 2020 13:00 without using screenshots as the loop's state source.
7. Searched the executable's RTTI for response semantics instead of building a screen classifier.
8. Added `scripts/win/rtti_index.js`, which parses the PE and MSVC RTTI structures directly from the on-disk `fm.exe` and emits class-name → vtable mappings.
9. `node scripts/win/rtti_index.js --contains RESPONSE ...` returned **352 response-family vtables** on this build.
10. Relevant classes include `TRANSFER_OFFER_RESPONSE`, `TRANSFER_NEGOTIATION_RESPONSE`, `TRANSFER_OFFER_CONFIRMATION_RESPONSE`, `MULTIPLE_TRANSFER_OFFER_RESPONSE`, squad-selection/registration responses, press-conference responses, work-permit responses and many other mandatory-event types.
11. Confirmed that concrete transfer-response vtables have live instances in writable memory. This establishes a route from "GAME time is blocked" to "which class of response is currently alive" without OCR.

## Did it achieve its goals?

**Partially, with a new durable primitive.** The repo can now generate the semantic vtable universe for required responses, and the live save demonstrated sequential football decisions. The remaining step is to identify the *active* response instance among stale/live copies and extract the event payload from memory.

The response detector is therefore not yet production-complete. A raw vtable hit only says an object of that class exists; FM keeps stale/UI generations around, so the active object still needs behavioural or object-graph validation.

## Why this route?

The evaluation loop must be fast enough to run through matches and many decision points. Full-screen capture/OCR/click reasoning was already known to be too expensive as the observation architecture. RTTI gives a cheap semantic index of FM's actual C++ event classes, while the existing writable-memory scanner can find their instances in a few seconds.
Screenshots were used only to validate newly discovered UI actions during reverse engineering. They are not the state source for the running controller.

## What did it learn?

- Required-response types are richly represented in FM's RTTI; this is not a narrow transfer-only seam.
- `RESPONSE` is a broad but useful static family: 352 vtables in this executable.
- Transfer decisions are genuinely sequential. The manager may need to decide, wait for the other club, then decide again on a changed offer.
- The authoritative GAME fingerprint remained independent of those UI decisions and continued to work as the liveness/progress oracle.
- The packed GAME date encoding can be partially interpreted (the year/calendar portion is visible), but production code should still use equality/change only until the representation is fully decoded.

## What went wrong / cautions

- Do not treat every live instance of a response-class vtable as the current blocker. Stale objects survive and can outnumber the live object, just as with lineup buffers.
- Do not use inbox strings or screenshots as the primary dispatcher. Those are useful validation aids only.
- The live save has moved well beyond the saved-on-disk 4 Oct baseline. It is disposable investigation state unless explicitly saved and promoted.

## Next session should probably

1. Build a live `find_responses` scanner from the static RTTI index and existing multi-pattern memory scan.
2. Capture the response-object set while blocked, then after resolving/advancing, and differential it to isolate current-generation objects/classes.
3. Follow pointers from the isolated response object to the underlying news/transfer/player objects and extract a machine-readable event payload.
4. Add a generic event-dispatch envelope and only then continue toward the Leicester match / Phase 3 match-state objects.
