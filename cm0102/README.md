# `cm0102/` — Championship Manager trial run

Everything about evaluating an older, simpler football management game as a testbed
lives in this directory. **It is a trial, not a migration.**

## The containment rule

This directory is deliberately quarantined so the trial stays reversible:

- **Nothing here imports from, or is imported by, `scripts/`, `cheat-table/` or
  `data/`.** Those are FM21's and stay untouched.
- **No FM21 file is edited to accommodate CM work.** If sharing the decision layer
  (`scripts/manager/pick_lineup.js` and friends) starts to look necessary, that is a
  *separate*, deliberate refactor — extracting a target-agnostic state/action
  interface — and it needs its own decision, not a quiet import.
- **Abandoning the trial means deleting this directory.** If that ever stops being
  true, the rule has been broken.

The one exception is documentation cross-links, which are one-way and harmless:
`docs/alternative-targets.md`, `README.md`, `PLAN.md` and `TODO.md` point *at* this
directory.

## Why this exists

FM21 works but is stuck on two things: the agent cannot advance the game, and
throughput makes PLAN.md's ~120-run experimental grid unaffordable. CM 01/02 is a
plausible answer to both, and a bad answer to some other things.

The full argument, including the case *against*, is in
[`../docs/alternative-targets.md`](../docs/alternative-targets.md). Read that before
doing anything here. Its conclusion in one line: **FM21 stays the experimental
target; CM is being evaluated as a fast pilot harness, and the spike decides whether
that is real.**

## What's here

| Path | What it is |
|---|---|
| `docs/spike.md` | The trial run itself — four exit criteria, step by step, executable cold |
| `docs/findings.md` | Where spike results get written. Empty until someone runs it |

No code yet, by design. The spike needs a Windows desktop (or Wine) and a CM 01/02
install; this repo's dev container has neither, so nothing here has been run.

## Status

**Not started.** Documentation only, written 2026-08-23. No CM binary has been run,
no claim in these documents has been verified live.
