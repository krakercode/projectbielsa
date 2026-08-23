# The CM trial run — a Phase 0 for Championship Manager

**Status: not started.** Nothing below has been run. Written 2026-08-23 by a session
with no desktop access.

This is deliberately shaped like FM21's Phase 0 (`docs/phase0-feasibility.md`): a
short, time-boxed feasibility check with hard exit criteria, run *before* committing
to anything. Read [`../../docs/alternative-targets.md`](../../docs/alternative-targets.md)
first — it explains why this is a pilot harness and not a migration, and it contains
the case against.

**Time box: one session.** If A and B are not both met by the end of it, the answer
is no and this directory gets deleted. That is a real, acceptable outcome — the
point of a spike is that failing is cheap.

---

## What is actually being tested

Not "is CM 01/02 nice". Three specific claims, each of which the FM21 work found
hard, plus one measurement:

| | Claim | Why it matters | FM21's answer |
|---|---|---|---|
| **A** | The game clock can be advanced by script, and the advance detected | The agent can pick a team but cannot play. Named "the real frontier" in `docs/session-log/2026-08-16-closing-the-loop.md` | Not solved. The in-game date isn't even readable |
| **B** | A squad can be read from cold, reproducibly, without scanning | 27 static pointer candidates, none survived a restart | Solved, but only by re-scanning 2.4 GB every run |
| **C** | A lineup can be set by script and verified | Needed for any loop at all | Solved, via drag-and-drop, ~86 s per decision |
| **D** | Measure wall-clock per match and per decision | PLAN.md names cost per run as *the* limiter | ~86 s/decision, matches in real time |

**A is the gate.** If advancing the clock is not straightforward, none of the rest
matters — that blocker is the entire reason this trial exists. Do A first and stop
early if it fails.

---

## Setup

Target build is **3.9.68** — the version the whole community standardises on, and
the only one the patchers and offset archives apply to. Anything else invalidates
every published offset.

1. Install CM 01/02 (freely distributed; the
   [CM0102 Starter Kit](https://github.com/JonBetts/CM0102-Starter-Kit) is the
   least painful route and handles the no-CD requirement).
2. Confirm the exe reports 3.9.68 before doing anything else.
3. Windows desktop is the low-risk option for the spike, since the FM21 tooling
   already lives on one. **Wine on Linux is criterion D's stretch goal, not a
   prerequisite** — do not let a Wine yak-shave consume the time box.
4. Start a save with a small database (one or two nations) — fast to load, fast to
   process, and enough to answer every question here.

Record the exact build, install path, and save name in `findings.md` before
starting. FM21 sessions repeatedly lost time to not knowing which process state a
number came from.

---

## A — advance the clock by script  ← the gate

**Exit criterion:** a script advances the game by N days without a human touching
it, and *independently confirms* the date changed.

Confirmation matters as much as the advance. The FM21 project's worst bug was a
nine-drag plan that stopped after one drag and reported success
(`2026-08-16-closing-the-loop.md`) — a script that clicks Continue and assumes it
worked reproduces exactly that failure.

Suggested order of attack:

1. **Find the in-game date first**, before automating anything. Value-scan for the
   displayed date, advance one day by hand, re-scan. A 2001 binary against a fixed
   build should yield a static address; if it does, that alone is a bigger result
   than anything FM21 achieved on this front. Note whether the address survives a
   **restart** — that is the specific thing FM21 failed.
2. **Then automate Continue** — a fixed-layout, non-animated 800×600 UI should make
   coordinate clicking reliable, unlike FM21's drag-and-drop.
3. **Then loop**: advance, read date, assert it moved, repeat. Advance 30 days.

**Also record:** what the game does when it *can't* continue (a match to play, a
decision to make, a news item modal). That is the real control-flow problem — an
agent that plays seasons has to recognise "the game is waiting for me" and why. It
is worth more than the clock itself, and FM21 never got far enough to face it.

---

## B — read a squad from cold

**Exit criterion:** a script produces a full squad — names, attributes, positions,
condition — from a cold start, and returns **identical output after a full restart
of the game**, with nothing hardcoded that a restart invalidates.

The restart is the whole test. Do not skip it; FM21's 27 static-path candidates all
looked fine until one.

Two routes; **try the save file first**:

1. **Save file.** Saves can be written uncompressed and the format is understood by
   the community's editor ecosystem. This is strictly better than memory if it
   works: reproducible, diffable, and it makes PLAN.md's "save snapshots at every
   decision point" free rather than a separate mechanism.
2. **Memory, at a static address.** The fallback. Community offset threads cite
   fixed exe-relative addresses (e.g. `00AE23BC`) against 3.9.68;
   [CM0102Patcher](https://github.com/nckstwrt/CM0102Patcher) is open source and
   worth reading for structure layouts rather than re-deriving them.

Two rules carried over from the FM21 work, both learned expensively:

- **Verify against the game's own UI, field by field.** Every bit of current
  confidence in the FM21 reads comes from doing this. A parser that produces
  plausible numbers is not a parser that produces correct ones — an FM21 buffer once
  parsed cleanly and returned *a different club's squad*.
- **Anchor on game data, never addresses.** `data/roster/` exists because UIDs and
  names survive restarts and addresses do not. Whatever the CM equivalent is, find
  it early.

---

## C — set a lineup and verify it

**Exit criterion:** a script changes the starting XI and the change is confirmed
both by re-reading state *and* on screen.

Keep the FM21 constraint that PLAN.md imposes structurally: **the write layer is
UI-driven by construction**, not by developer discipline (see the note at the top of
`scripts/lua/actions.lua`). A memory-write shortcut here would quietly invalidate
the human-equivalence claim the whole experiment rests on. The fixed, static UI
should make this *easier* than FM21, not a reason to cheat.

---

## D — measure

**Exit criterion:** real numbers in `findings.md`, not adjectives.

- Wall-clock to process one match day; to process one full season.
- Wall-clock for one read → decide → act cycle, against FM21's **86 s**.
- Whether it runs under Wine + Xvfb at all, and whether two instances run in
  parallel against separate save directories. This carries the entire parallelism
  argument and is currently pure assertion.

Then do the arithmetic PLAN.md asks for and never got: **cost per season**, and what
that implies for a 4-cell × N-seed × M-model grid. If CM makes ~120 runs affordable
and FM21 does not, that is the finding.

---

## What would make the answer "no"

Write these down now so the decision isn't rationalised later:

- **A fails** — the clock can't be advanced or the advance can't be detected. Then CM
  solves nothing FM21 hasn't, and the trial is over.
- **B needs scanning anyway** — no static address, no usable save format. The main
  engineering advantage evaporates.
- **Speed isn't materially better.** Everything here rests on "old game, therefore
  fast", which is currently an assumption, not a measurement.
- **No per-player knowledge model** for human mode (open question 1 in
  `alternative-targets.md`). This wouldn't kill the pilot-harness use, but it does
  mean CM can never host the real experimental condition — record it explicitly
  rather than discovering it in Phase 5.

---

## Afterwards

1. Fill in [`findings.md`](findings.md) — numbers and verification evidence, not
   impressions. Honest about what was checked versus assumed, per the session-log
   template's own standard.
2. Write a session log (`docs/session-log/`), as `CLAUDE.md` requires.
3. Make the call in `../../docs/alternative-targets.md` § 6: pilot harness, fallback
   to CM 03/04, or drop it.
4. **Only then** consider extracting a target-agnostic state/action interface from
   `scripts/manager/`. That refactor is worth doing on its own merits —
   `run_decision.js` hardcodes `powershell.exe` and a sidebar click coordinate — but
   it is not spike work, and doing it early would break this directory's containment
   rule for a target that might not survive the week.
