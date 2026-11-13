# Session Log: press-question reader and between-match dispatcher (offline)

## Session metadata

- **Date:** 2026-11-13
- **Phase(s) touched:** Phase 4 required-response dispatch
- **Starting point:** `run_press_conference.js` could read the answers and act on them, but it could not read the question text. See `2026-09-09-press-conference-memory-path.md` and `2026-09-09-eod-leicester-match-gate.md`.
- **Access available this session:** code only. There was no access to live process memory. Computer use reached the PC through screenshots and clicks, but Remote Control was off, so no script could run on the machine.

## What did it do?

1. Used computer use to launch FM21 through Steam and load the most recent save, "Claude Anthropic - Aston Villa". It shows the Home screen on Sat 17 Oct 2020, matchday for Leicester v Aston Villa. The game was not advanced or saved. An FM pop-up was hidden behind a window that computer use isn't allowed to show; pressing Escape dismissed it.
2. Added `scripts/manager/press_question.js`. This is pure logic: it extracts UTF-8 strings (accented names stay intact), filters for question-like text, and makes a fail-closed selection that records offset-path provenance.
3. Added `scripts/manager/read_press_question.js`, the live reader. It requires a current question from `read_press_state.js`. It then walks a bounded pointer graph from several roots: the current `PRESS_CONFERENCE_QUESTION`, plus the live instances of these interaction and press panel RTTI classes:
   - `INTERACTION_GROUPED_RESPONSE_SELECTOR_PANEL`
   - `PRESS_CONFERENCE_PANEL`
   - `INTERACTION_PRESS_CONFERENCE`
   - `INTERACTION_QUESTION`

   The walk goes to depth 3, reads 768 bytes per node and stops at 2500 nodes. It makes one `dump_many.ps1` call per depth level. It returns a question only when exactly one candidate remains, or exactly one sits under the `question` root. It has a `--discover` flag and an empty `PINNED_PATHS` list, which should be filled from the first live run.
4. Added `scripts/manager/between_match_events.js`, a generic dispatcher, and `scripts/manager/events/press_conference.js`, its first handler. The envelope has this shape: `{event_type, ready, blocked_reason, payload, actions, provenance}`. Only `payload` goes to the model; the click geometry lives in `actions`.
5. `run_press_conference.js` now gets its prompt from the handler and includes the question text. If the text can't be read, it still refuses unless `--allow-choice-only` is passed.
6. Added `scripts/manager/test/*.test.js`, 11 tests using `node:test`. Run them with `node --test scripts/manager/test/*.test.js`. All pass on Linux with Node 22.

## Did it achieve its goals?

**Partially.** The goal was a working question-text reader as the first between-match event.

- The dispatcher, the handler and the runner wiring are done and covered by unit tests.
- The reader is **unverified**. Nothing here has touched live memory. Its assumptions are:
  - the question text is stored as printable UTF-8;
  - it can be reached within 3 pointer hops of one of the roots above;
  - it contains a `?`.

  Any of these could be wrong.
- The current save is already past the Leicester pre-match press conference. Testing live therefore needs the next conference, either post-match or before the next fixture.

## Why did it do what it did?

- **Discovery walk instead of a guessed offset.** The answers sit behind BUTTON+0x1B0 → handle+4, but nobody knows which object owns the question text. A fixed guess would fail silently. The walk records the path of each candidate so the first live run can pin it.
- **The `?` requirement and the response exclusion** make it hard for an answer to be mistaken for the question. Answers can contain `?`, which is why they are excluded by exact text.
- **Template strings (`[%...]`) are rejected.** The model has to see the formatted text that a human sees, not FM's template.
- **Fail closed.** This matches the 2026-09-09 rule that the model must never answer blind.

## What did it learn?

- Computer use **cannot operate the Claude desktop app**, so Remote Control can't be turned on remotely. Victoria has to enable it under Settings > Claude Code.
- On this PC, the FM21 window belongs to `fm.exe` and needs its own computer-use grant. Opening "Football Manager 2021" by name fails; launching from Steam's Play button works.
- When an FM pop-up is hidden behind a window computer use can't show, FM looks dimmed and ignores clicks. Escape clears it.

## What went wrong?

- None of the new memory-reading code has run against fm.exe. The PowerShell side (`dump_many.ps1`, `scan_mem.ps1`) is reused unchanged, but the call shapes are new.
- The RTTI root class names are guesses. If none of them exist, the reader falls back to the `question` root alone.
- The walk could be slow. At 2500 nodes × 768 bytes it is about 1.9 MB across 4 PowerShell calls, which should be acceptable but hasn't been measured.

## Next session should probably

1. Start Remote Control on the repo folder. At the next press question, run `node scripts/manager/read_press_question.js --discover`. Confirm the text against the screen once, then pin the path in `PINNED_PATHS`.
2. If there are no candidates: increase `DEPTH`, try UTF-16 decoding, or diff the `question` object's pointees between two consecutive questions.
3. Then run `node scripts/manager/run_press_conference.js` without `--allow-choice-only`, and add the next handler (transfer offers) to `between_match_events.js`.
