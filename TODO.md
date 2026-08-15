# TODO — live work queue

Sessions start cold, so this is the "what's next" list. `PLAN.md` is strategy,
`docs/session-log/` is history, this is the queue. **Keep it current** — move
items to Done with the commit that closed them, and delete stale entries.

Last updated: 2026-08-15

---

## Next up

- [ ] **Fixtures / schedule** — visible on the Competitions and Schedule screens;
      no memory structure located yet.
- [ ] **League tables** — the full EPL table renders on the competition page, so
      the data is there; find the backing structure.
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
