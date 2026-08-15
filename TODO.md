# TODO — live work queue

Sessions start cold, so this is the "what's next" list. `PLAN.md` is strategy,
`docs/session-log/` is history, this is the queue. **Keep it current** — move
items to Done with the commit that closed them, and delete stale entries.

Last updated: 2026-08-16 (table render loop found; Phase 2 is next)

---

## Manager stack (Qwen) — working, read-only

Ollama + `qwen3:8b` installed, `scripts/manager/` runs `pick_lineup` end to end
in both modes. See `docs/manager-setup.md`.

- [ ] **Second model** — the Phase 4 exit criterion is the same task through two
      adapters. `ClaudeProvider` is a stub that throws. Hosted model + API key,
      or a second local model.
- [ ] **Exercise the `tools` (agentic loop) strategy at least once.** It is
      written but has never run — untested code, which is the exact failure mode
      that bit this project before.
- [ ] **Replace the placeholder human-mode masking.** It buckets true CA, which
      still leaks ordering. Marked `masking: "placeholder-not-phase5"` in the
      data. Do not publish anything off it.
- [ ] Extract the prompt scaffold from `pick_lineup.js` into `prompts.js` when a
      second decision event lands.

## Next up

- [x] **League table — render loop FOUND, league position readable.**
      `fm.exe+1455A87E3`, `RBX` = club, visited in exact table order 1st→20th.
      See `docs/phase1-notes.md` and
      `docs/session-log/2026-08-16-table-render-loop.md`.
- [ ] **P/W/D/L/Pts — confirmed NOT stored as integers.** Swept the whole render
      path (5 structures + 15 per-club series, up to 8 KB each, widths 1/2/4).
      FM derives the table from results. **Do not re-scan.** If the numbers are
      wanted, decide between:
      1. Intercepting the string formatting on the render path (`R8` carries
         inline strings, so that is where the numbers become visible), or
      2. OCR via `scripts/vision/` — arguably more human-faithful for the
         human-knowledge condition, since it reads what a player actually sees.
      Note position alone may be enough: it is `PLAN.md`'s primary outcome measure.
- [ ] **Player season stats (apps/goals/ratings)** — promising accidental lead:
      the 100-byte-stride runs found by the played 3→4 scan are probably these,
      not table rows. Worth following; it's a Phase 1 deliverable in its own right.
- [ ] **Fixtures** — partial. 16-byte records holding a club pointer plus two
      4-byte fields at `CD45F680`, not yet proven to be fixtures; no scoreline or
      date identified.
- [ ] Confirm or refute: **is the table derived from results rather than
      stored?** Still the leading hypothesis and it changes the target entirely.
- [ ] **Locate the competition object.** Still not found as a static structure,
      but two of its loops are now known: the alphabetical 20-club walk
      (`1440BCF1D`) and the ranked table walk (`1455A87E3`). `BBD9xxxx+0x30` is a
      per-club competition record holding its club pointer. The iterator itself
      was not visible even at 160 stack qwords, so the collection base sits
      further up the frames or the loop is index-based.
- [ ] **Cache the located vector header per session** so `locate_vector()`'s
      ~2 minutes of scanning is paid once, not per dump.
- [ ] **Cold-read demo**: pre-commit to a club by table position, state priors
      blind, then reveal. The contamination demonstration agreed on 2026-08-14.

## Phase 1 exit criterion (the actual remaining scope)

Player, staff and club layers are done and verified. The exit criterion — "one
script call produces a clean JSON snapshot of an entire save's key state" — needs:

- [ ] Fixtures / schedule
- [ ] League tables
- [ ] Transfer shortlist
- [ ] A single `dump_state()` entry point that assembles all of the above,
      including the squad via `locate_vector()` rather than the selection only

## Experiment setup (Phase 4+ prerequisites, PLAN.md)

- [ ] **Build the randomised base save**: holiday forward 15–20 seasons with only
      England's top two tiers loaded, then pick a club matching a target profile.
      Build once, branch every randomised-column run from it. Long unattended job.
- [ ] Enable "real-world fixtures for the first season" for the real-world column.
- [ ] Decide the short scenario shape (one transfer window? ten fixtures with a
      fixed squad?) — needed before the 2×2 grid is affordable.
- [ ] Measure cost per run (decision points × tokens) before committing to the grid.
- [ ] Save snapshots at every decision point, for cross-model replay on matched seeds.
- [ ] Anonymised serialisation option in the JSON layer (omit names/club identity).
- [ ] Contamination probe: ask the model to name the club from a squad list.
- [ ] Prediction logging for hidden values from day one — cheap insurance so the
      deferred leak audit is retrospective rather than a full re-run.

## Optional / deprioritised

- [ ] **Two-pointermap compare pointer scan.** The 27 single-snapshot candidates
      all failed validation. This is the proper escalation, but a static path is
      an optimisation rather than a blocker — see `docs/phase1-notes.md`.
- [ ] Test whether FM reproduces regen intakes on save reload (assume not; the
      matched-seeds design doesn't depend on it either way).

## Done

- [x] Verify `dump_state.lua` live — found and fixed reversed pointer offsets (`51d363e`)
- [x] Full-squad read via the squad `std::vector` (`1608f2b`)
- [x] Exact 23/23 squad read via vector header (`af3fbaf`)
- [x] Verify the staff path — all 83 fields (`af3fbaf`)
- [x] Pointer scan producing 27 candidate static paths (`d311e6c`)
- [x] Reframe PLAN.md as an evaluation project; 2×2 design (`73b9387`, `bfabfee`)
- [x] Confirm FM21 has no database randomisation option (`79f8dd6`)
- [x] Validate the 27 pointer paths — **none survive a restart** (`571d4b1`)
- [x] `locate_vector.lua` reproducing the squad vector from cold (`e677a0f`)
- [x] `pCurrentClub` — needs the hook enabled *and* a club screen visited
      afterwards; all 30 club fields verified against Liverpool's page. Also
      retargets to any club you view, so opposition data is readable.
- [x] **CE's debugger works on FM21** — access *and* execute hardware breakpoints
      fire and clear cleanly with no crash; anti-tamper does not block them
- [x] All 20 Premier League club object addresses captured
      (`scripts/lua/find_competition.lua`)
