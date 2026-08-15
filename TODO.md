# TODO — live work queue

Sessions start cold, so this is the "what's next" list. `PLAN.md` is strategy,
`docs/session-log/` is history, this is the queue. **Keep it current** — move
items to Done with the commit that closed them, and delete stale entries.

Last updated: 2026-08-15 (after the debugger/league-table session)

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

- [ ] **League table — six approaches now failed**, but the debugger route opened
      real ground (see `docs/phase1-notes.md` and
      `docs/session-log/2026-08-15-debugger-league-table.md`). Next, in order:
      1. **Break on the caller.** The render loop runs at constant `RSP=811ECF0`,
         return chain `1440DB515` → `1440BE24A` → `1455A87E3`. An execute
         breakpoint on `1440DB515` lands inside the loop where the iterator and
         collection base are live. `scripts/lua/watch_table_render.lua` needs only
         an address change.
      2. **Dump `BBD9xxxx` wider.** `+0x30` is the club pointer, so these are
         per-club competition records; stats aren't in the first 0x400. Re-run
         `dump_league_rows.lua` with range 0x2000.
      3. Still available: one more sim + next-scan for **5** to split the 5,081
         survivors — the found-list is *still live in the CE GUI*, but it dies the
         moment CE restarts.
      4. Do **not** redo the `Club*` fixed-stride array scan; 919 hits × 17 strides
         topped out at 7/20.
- [ ] **Player season stats (apps/goals/ratings)** — promising accidental lead:
      the 100-byte-stride runs found by the played 3→4 scan are probably these,
      not table rows. Worth following; it's a Phase 1 deliverable in its own right.
- [ ] **Fixtures** — partial. 16-byte records holding a club pointer plus two
      4-byte fields at `CD45F680`, not yet proven to be fixtures; no scoreline or
      date identified.
- [ ] Confirm or refute: **is the table derived from results rather than
      stored?** Still the leading hypothesis and it changes the target entirely.
- [ ] **Locate the competition object.** Still not found, but no longer blind:
      a competition-scoped collection of exactly the 20 PL clubs provably exists
      (proven 2026-08-15 by breakpoint — one loop, alphabetical, constant `RSP`),
      and `BBD9xxxx+0x30` is a per-club competition record holding its club
      pointer. Getting the loop's collection base is item 1 above.
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
