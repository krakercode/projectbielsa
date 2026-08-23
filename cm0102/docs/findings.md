# CM trial run — findings

**Nothing has been run.** This file is a structured place for spike results to land,
created 2026-08-23 alongside [`spike.md`](spike.md). Every field below is empty
because no CM binary has been executed by this project.

Fill it in *while* running the spike, not afterwards from memory. Numbers and
verification evidence, not impressions — the standard in
`docs/session-log/TEMPLATE.md` applies here: **be honest, not impressive**, and mark
anything guessed as guessed.

---

## Environment actually used

| | |
|---|---|
| Date run | — |
| CM version | (must be **3.9.68** — anything else invalidates every published offset) |
| Install path | — |
| OS / Wine version | — |
| Save name, database size, club | — |

---

## A — advance the clock  ← the gate

- **Met / not met:** —
- In-game date located at: — (static address? survived a restart? **state which**)
- How Continue was driven: —
- How the advance was *independently confirmed*: —
- Days advanced in one unattended run: —
- **What blocks Continue** (matches, decisions, news modals) and how the game
  signals it: —

> This is the criterion FM21 never met. If it fails here, stop — see spike.md
> § "What would make the answer no".

## B — read a squad from cold

- **Met / not met:** —
- Route taken (save file / static memory address): —
- **Identical output after a full restart?** —
- Field-by-field verification against the game's own UI — how many fields, against
  which player, what disagreed: —
- Anchor used instead of addresses (the CM equivalent of `data/roster/`): —

## C — set a lineup

- **Met / not met:** —
- How the write was driven (must be UI-driven by construction): —
- Verified by re-reading state: —
- Verified on screen: —

## D — measurements

| Metric | CM | FM21 (for comparison) |
|---|---|---|
| One match day processed | — | real time |
| One full season processed | — | not achievable |
| One read → decide → act cycle | — | **86 s** |
| Runs under Wine + Xvfb | — | n/a (Windows only) |
| Two instances in parallel | — | untested |

**Cost per season, and what it implies for a 4-cell × N-seed × M-model grid:**
— (this is the arithmetic PLAN.md asks for and the project has never done)

---

## Open questions from `docs/alternative-targets.md` § 7

Answer whichever the spike happened to settle; leave the rest marked unresolved
rather than guessing.

1. Per-player scouting knowledge model for human mode? —
2. Actual season processing speed? —
3. Wine + Xvfb, parallel instances? —
4. CM 03/04's open RE material? —
5. In-game date reachable statically? —

---

## The call

- **Outcome:** pilot harness / fallback to CM 03/04 / drop it — *not yet decided*
- **Reasoning:** —
- Recorded in `docs/alternative-targets.md` § 6: —
