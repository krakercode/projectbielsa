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
## What remains / cautions

- The current question text is not yet generically decoded. Rendered fragments exist in memory, but the clean ownership path from the active `PRESS_CONFERENCE_QUESTION` to those strings is still unresolved.
- Raw RESPONSE-vtable presence is not enough to identify the current blocker because FM retains stale generations.
- All live heap addresses in this log are intentionally omitted from the durable findings. Re-derive live instances from RTTI/vtable scans after restart.
- `read_press_choices.js` is press-conference-specific today; do not present it as a generic event dispatcher yet.
- The running save is disposable investigation state and has not been promoted to a new disk-save baseline.

## Next session should probably

1. Use the `PRESS_CONFERENCE_EDIT_SESSION` progress differential to identify the active question object without screen input.
2. Resolve the active question object's formatted text from memory, including multi-fragment questions.
3. Emit a machine-readable press event `{question, choices, metadata}` and route it to the manager provider.
4. Apply the selected response using the already decoded memory-derived button geometry and verify the edit-session progress counter changes.
5. Repeat across the rest of the conference, then fold the press handler into generic required-response dispatch and continue toward the Leicester match / Phase 3 live-match objects.
