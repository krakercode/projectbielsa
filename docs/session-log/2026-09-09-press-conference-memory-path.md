# Session Log — press-conference memory path

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 4 required-response orchestration / Phase 3 memory-state prerequisite
- **Starting point:** response RTTI classes were indexed, but the live blocker still needed a memory-only payload/action path.
- **Live scenario:** Aston Villa, 16 Oct 2020, pre-match press conference before Leicester.

## What was built

1. Added `scripts/manager/find_responses.js`. It generates the RESPONSE vtable set from `rtti_index.js` and scans writable FM memory in one pass.
2. Extended `scripts/win/rtti_index.js` to expose MSVC CompleteObjectLocator `object_offset` and `cd_offset`.
3. Added `scripts/manager/read_press_choices.js`, a memory-only reader for live press-conference responses.
4. Added `scripts/win/walk_ptrs.ps1`, a bounded read-only pointer-graph helper used for opaque-object exploration.
5. Kept screenshots out of the observation path. They were used only after memory findings to confirm object meaning during reverse engineering.

## Live findings

- The blocked Leicester press conference produced a current generation of `INTERACTION_GROUPED_RESPONSE_SELECTOR_PANEL` / `INTERACTION_RESPONSE_WIDGET` objects.
- `INTERACTION_RESPONSE_WIDGET` has three vtables in RTTI; `object_offset == 0` identifies the primary vtable, so the reader no longer relies on a per-process address guess.
- Each live response widget points at its `BUTTON` at `widget+0x1A0`.
- The BUTTON's `+0x1B0` field is a text handle; the UTF-8 response begins at `handle+4`.
- Widget floats at `+0x5C/+0x60/+0x64/+0x68` are x/y/width/height. Sorting by x reproduces the response order.
- On the first question, `read_press_choices.js` recovered all five visible answers exactly and returned centre-click coordinates.
- Qwen (`qwen3:8b`, pragmatic profile) chose answer index 0. The action was applied with SendInput using the memory-derived coordinate.
- FM advanced to the next press question and the same reader immediately returned a new set of five answers. This proves the path is dynamic, not hardcoded to one screen.
- The live `PRESS_CONFERENCE_EDIT_SESSION` contains an eight-element vector of `PRESS_CONFERENCE_QUESTION` objects and a thirteen-element vector of `PRESS_CONFERENCE_JOURNALIST` objects, matching the meeting attendance.
- Within a question, `+0x20` points to a `db::MEDIA_SOURCE` and `+0x28` to a `db::JOURNALIST`.
- A before/after diff of the first 2 KiB of `PRESS_CONFERENCE_EDIT_SESSION` after answer one changed only three bytes. `+0xE0` changed from `0` to `1`; `+0xF0/+0xF1` also changed. Treat `+0xE0` as a strong progress-counter lead, not yet a durable decoded field.

## Validation

`node scripts/manager/read_press_choices.js` returned five first-question choices at x-centres 340, 650, 960, 1270 and 1580. After Qwen selected/clicked index 0, the same command returned five different loan-policy answers for question two.

The first answer selected by Qwen was:

> We need to continue to work hard and make sure we play to our full potential

No screenshot text, OCR, or pre-known response strings were required by the reader.
## Continuation — conference completed and exited

- `read_press_state.js` was added around the live `PRESS_CONFERENCE_EDIT_SESSION`. It resolves the dynamic question vector, `+0xE0` progress counter and current question pointer while one is active.
- FM inserted a follow-up question during the conference, growing the vector. This proved the question list is dynamic rather than a fixed agenda.
- Qwen continued selecting from memory-read response choices. The write side used only memory-derived button rectangles plus SendInput.
- At terminal state `+0xE0` reached **10** while the question vector contained **9** entries. Therefore the field is an answered-response/progress counter, not an always-valid vector index.
- More importantly, stale response widgets remained after the final question with plausible geometry/text. A controller that only looked for response widgets could click an old answer. The runner now has a hard semantic gate: no current question means response widgets are never read or actioned.
- `read_ui_buttons.js` was added as a generic memory reader for primary BUTTON / ICON_BUTTON objects. It reads the same text-handle and geometry seams used by the press-choice reader.
- At the end it located **Continue To Summary** as a BUTTON. On the summary screen it located **Leave Press Conference** as an ICON_BUTTON from memory, and the click used that object's centre.
- Exit was verified: the live primary `INTERACTION_SUMMARY_PRESS_CONFERENCE_PANEL` disappeared and a post-exit button scan found no press-conference/summary terminal controls.
- A one-time screenshot was used only after reaching the summary to confirm the newly decoded semantics. It was not an observation source for the loop.

## Safety / validity status

The press conference is **complete and exited**, but the event handler is not yet publishable. The formatted current-question text is still not generically decoded. The reverse-engineering run therefore made later choices from answer text without full question text. That is useful for validating the memory/action plumbing, but must not be presented as a valid evaluation condition.

`run_press_conference.js` now refuses that behaviour by default. It requires an explicit `--allow-choice-only` flag to reproduce the RE experiment, and it verifies semantic progress after each answer. This makes accidental blind press decisions fail closed.

The remaining press-specific task is to map the authoritative current `PRESS_CONFERENCE_QUESTION` to its formatted question text. After that, emit a complete event payload, fold it into generic required-response dispatch, and continue with the Leicester match / Phase 3 live-match state.