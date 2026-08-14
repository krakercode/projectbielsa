# Session Log Template

This project spans many separate Claude sessions with no shared memory between them — each one picks up cold, working from PLAN.md, the docs/, and git history. This log exists to carry forward the things that *aren't* in the code: why a call was made, what turned out to be wrong, what's still unverified.

**Fill this out at the end of every work session**, before ending the conversation. Copy this file to `docs/session-log/YYYY-MM-DD-short-topic.md` (e.g. `docs/session-log/2026-08-14-dump-state-lua.md`), fill it in, and commit it alongside whatever code/doc changes the session produced.

**Be honest, not impressive.** A log that only records successes is worse than no log — the next session needs to know what to avoid, not just what to feel good about. If something was guessed rather than verified, say so. If a whole approach turned out to be wrong, say that plainly rather than burying it. Specificity beats politeness: "assumed X, turned out Y" is more useful than "encountered some challenges."

---

## Session metadata

- **Date:**
- **Phase(s) touched:** (e.g. Phase 0, Phase 1)
- **Starting point:** one sentence on what state the project was in when this session began — link the previous session log entry if there is one
- **Access available this session:** (e.g. "live Cheat Engine + FM21 access", "code/docs only, no desktop access")

## What did it do?

Concrete, factual, in order. Not a summary of intentions — an account of what actually happened. Include:

- Files created/modified/deleted (real paths, not vague descriptions)
- Commands run, tools used, external resources fetched
- Decisions made and where they're recorded (e.g. "chose X over Y, see docs/foo.md")
- Commits made (reference the commit message or hash)

*(If a planned action was attempted and failed or was abandoned partway, record that here too — "did X" and "attempted X, abandoned because Y" are both facts that belong in this section.)*

## Did it achieve its goals?

State the goal(s) the session started with, then answer plainly: yes / no / partially, against each one specifically.

- If partial or no: what's the actual gap between where things ended up and the goal?
- If yes: what's the exit criterion or evidence that confirms it (a test result, a live confirmation, a specific observed output) — not just "should work"?
- Don't round up. "Wrote a script that should do X but wasn't tested" is *not* "achieved X."

## Why did it do what it did?

The reasoning behind non-obvious choices — especially ones a future session might otherwise second-guess, redo, or accidentally undo. Cover:

- Any point where the session deviated from PLAN.md or an earlier doc's stated approach, and why
- Tradeoffs considered and rejected (e.g. "considered A, went with B because...")
- Assumptions made when information was missing, and what they were based on

*(The point of this section is to save a future session from re-deriving — or worse, silently reversing — a decision that was actually made for a good reason.)*

## What did it learn?

Genuinely new information discovered this session that wasn't known before it started — the kind of thing that should update how future sessions approach the project. Examples of the right grain of detail:

- A concrete fact about the game/tooling (a pointer offset, an API quirk, a version mismatch)
- Something about the environment (what's installed, what access is/isn't available, a platform limitation)
- A technique that worked (or didn't) that's worth reusing (or avoiding)

*Not* things that were already documented elsewhere before this session — this section is for what's new.

## What went wrong?

Blockers hit, mistakes made, dead ends, wrong assumptions that had to be corrected mid-session, things that still need to be redone or fixed. Include:

- Anything that cost significant time or had to be backed out
- Anything left in a broken or half-finished state (and where)
- Anything the session *couldn't* do and why (missing access, missing information, a hard technical blocker) — distinct from things simply not attempted
- Open questions the session surfaced but didn't resolve

*(An empty section here is suspicious more often than it's true. If truly nothing went wrong, say so explicitly rather than leaving it blank — a blank section is ambiguous between "nothing went wrong" and "didn't bother checking.")*

---

## Next session should probably

Optional, but useful: one to three concrete next steps, written for a session that has no memory of this one. Point at specific files/docs, not vague intentions.
