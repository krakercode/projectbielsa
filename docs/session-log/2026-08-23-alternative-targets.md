# Session Log — 2026-08-23 (evaluating an older, simpler game as a target)

## Session metadata

- **Date:** 2026-08-23
- **Phase(s) touched:** none directly — this is a target/strategy question sitting
  above the phase structure. Touches PLAN.md's "Open Risks" and "Variance and cost".
- **Starting point:** Phase 4's loop works end to end (see
  `docs/session-log/2026-08-16-closing-the-loop.md`), but the agent cannot advance
  the game and throughput makes the ~120-run experimental grid unaffordable.
- **Access available this session:** **Code, docs and web only.** Linux dev
  container — no desktop, no FM21, no Wine, no CM binary. **Nothing was verified
  live.** This is the single most important caveat on everything below.

## What did it do?

The user asked whether decompiling an earlier, simpler game (a Championship Manager
title) would make life easier. Researched it and wrote it up. No code.

1. Read the current state: `README.md`, `PLAN.md`, `TODO.md`,
   `docs/session-log/2026-08-16-closing-the-loop.md`, and the interfaces in
   `scripts/manager/squad_state.js` and `run_decision.js`.
2. Web research on the CM 01/02 reverse-engineering landscape: `nckstwrt/CM0102Patcher`
   (open-source C#), CMRTE, the champman0102.net offset threads, the Starter Kit,
   Wine/Linux reports, and CM 03/04 as a fallback.
3. Asked the user three framing questions. Their answers shaped the recommendation:
   **CM as a dev harness with FM21 retained as the target**; **research only, no
   code**; **let a spike decide between CM 01/02 and 03/04**.
4. Created:
   - `docs/alternative-targets.md` — the decision document
   - `cm0102/README.md` — containment charter for the trial
   - `cm0102/docs/spike.md` — the trial run, four exit criteria, executable cold
   - `cm0102/docs/findings.md` — empty structured place for results to land
5. Wired it in so a cold session finds it: a bullet in `PLAN.md` § Open Risks, a
   status paragraph and repo-layout line in `README.md`, a queued (unstarted)
   section in `TODO.md`.

Mid-session the user extended the ask from "research only" to "build documentation
for the CM trial run and then get to work, cleanly separated". The documentation and
separation were done; **"get to work" could not be, because the spike needs a
desktop and a CM install this container doesn't have.** Said so rather than
inventing runnable-looking code that had never been run — this project has been
bitten twice by untested code paths (`TODO.md` still lists the `tools` strategy as
written-but-never-run).

## Did it achieve its goals?

**Goal: answer whether an older game is easier. Yes.** With a concrete answer rather
than a vibe: the cost of switching is "rebuild the read/write layer", roughly 2–3
sessions of the ~8 done, because PLAN.md's experimental design and most of
`scripts/manager/` are target-agnostic. That number is the useful output.

**Goal: document the trial run. Yes.** `cm0102/docs/spike.md` has four exit criteria
with a named gate (advancing the clock), an explicit time box, and a written-down
list of what would make the answer "no".

**Goal: keep it separated from FM work. Yes, verifiably.** All new content is under
`cm0102/` or is a doc cross-link. No file under `scripts/`, `cheat-table/` or
`data/` was touched; `git diff --stat` confirms it.

**Goal: run the trial. No — blocked, not skipped.** No CM binary was executed. Every
CM claim in these documents comes from community sources and is marked as such.

## Why did it do what it did?

- **Recommended *against* switching the experimental target**, despite the
  engineering case for CM being strong. PLAN.md's premise is measuring whether LLMs
  can play a *complex* game under human-equivalent constraints; on a shallow game
  that finding is weaker, and no amount of engineering convenience repairs it. The
  pilot-harness framing takes the throughput win without paying that price.
- **Reframed "decompile" as targeted RE.** Full decompilation of a ~6 MB MSVC C++
  binary is person-years. Said this explicitly in § 1 of the doc so a future session
  doesn't scope a decomp project off the branch name.
- **Made advancing the clock the gate.** It is the blocker FM21 never solved and the
  entire reason the trial exists; if CM doesn't fix it, nothing else matters.
- **Deferred the target-agnostic interface refactor.** It is genuinely worth doing —
  `run_decision.js` hardcodes `powershell.exe` and a click coordinate — but doing it
  now would break `cm0102/`'s containment rule for a target that might not survive
  the spike. Noted in `TODO.md` as post-spike.
- **Wrote `findings.md` empty rather than not at all**, so results land somewhere
  structured instead of only in a session log.

## What did it learn?

New facts, all from community sources and **none verified against a binary**:

- The CM 01/02 community standardises on **one build, 3.9.68**, and forum threads
  cite **fixed exe-relative data addresses** (e.g. `00AE23BC`). That is the direct
  counterpart to this project's cleanest negative result: 27 static pointer
  candidates for FM21, none surviving a restart.
- `nckstwrt/CM0102Patcher` is **open-source C#** with structure knowledge embedded in
  patching code (no formal offset spec), alongside CM0102Loader and CMRTE.
- The binary carries **assertion strings naming its own source files and line
  numbers** (`player_stats.cpp 3828` in a community bug report) — materially useful
  for RE.
- Saves can be written **uncompressed** and have a mature editor ecosystem, so state
  could come off disk rather than a moving heap — which would make PLAN.md's
  "save snapshots at every decision point" free.
- It runs under **Wine on Linux** (documented down to Raspberry Pi), and is freely
  distributed with no anti-tamper.
- **Contamination is worse here, not better.** CM 01/02's match-engine exploits (the
  Creativity bug, the formation exploits, the wonderkid lists) are famous and
  thoroughly written about online, which collides head-on with PLAN.md's "You cannot
  instruct a model to forget" section.

## What went wrong?

- **The spike could not be run.** No desktop, no Wine (`which wine` → nothing), no
  CM install. The trial run is fully specified and entirely unexecuted. This is the
  main gap between what was asked and what was delivered.
- **An early framing mistake, corrected before writing:** started from "which game
  is easier to reverse-engineer" when the decisive question is "how much of eight
  sessions survives a switch". The transfer analysis (`alternative-targets.md` § 3)
  came out of that correction and is the most useful part of the document.
- **CM 03/04 was researched shallowly.** Found an active patching community but
  nothing like CM 01/02's offset archive. Not enough to properly rank it as the
  fallback — it is listed as open question 4.
- **Five open questions are genuinely unresolved**, listed in
  `alternative-targets.md` § 7. The one that matters most: **does CM 01/02 have a
  per-player scouting knowledge model?** PLAN.md Phase 5 wants to read FM's own
  "known-to-user" flags so human mode is authoritative. If CM has no equivalent, it
  can never host the real experimental condition — only the pilot. A community
  "hide all stats" patch exists, but that is attribute visibility, not a knowledge
  model, and the two were not conflated.
- **Every speed claim is an assumption.** "Old game, therefore fast" is the load-bearing
  premise of the whole throughput argument and has not been measured once.

---

## Next session should probably

1. **Run the spike, if there's desktop access** — `cm0102/docs/spike.md`, criterion
   A first, stop early if it fails. Results into `cm0102/docs/findings.md`.
2. **If there's no desktop access, do not touch `cm0102/`** — there is nothing
   useful to do there without the game, and writing unrun CM code is exactly the
   failure mode this project already has twice.
3. **The FM21 queue is unchanged and still the priority**: exercise the `tools`
   agentic strategy (still never run), and analyse cost per decision from the data
   `run_decision.js` already logs — that last one feeds directly into the CM
   decision, since the comparison needs both sides measured.
