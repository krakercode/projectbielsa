# Session Log — 2026-08-15 (pointer path validation)

## Session metadata

- **Date:** 2026-08-15
- **Phase(s) touched:** Phase 1 (squad vector location, pointer path validation), plus PLAN.md experimental design
- **Starting point:** 27 unvalidated candidate static pointer paths to the Villa squad vector, saved in `D:\ptrscan\squadvec_L4.PTR`. Squad read working at 23/23 via a hand-found vector header. See `docs/session-log/2026-08-14-live-squad-read.md`.
- **Access available this session:** Full live desktop control; FM21 and Cheat Engine relaunched from cold.

## What did it do?

1. **PLAN.md reframing** (before touching the game). Recorded that this is an evaluation project rather than a bot; recast cheat mode as the oracle/upper bound; added an Experimental Design & Validity section (contamination, observation budget, UI-equivalent writes, baselines, variance/cost, metrics, deferred leak audits). Commits `73b9387`, `bfabfee`, `79f8dd6`.
2. **Structured the experiment as a 2×2** at the user's suggestion — database (real vs randomised) × information (human vs perfect). This is a better frame than the separate concerns previously written down; the interaction term (does world knowledge substitute for scouting?) is the interesting cell.
3. **Confirmed FM21 has no database randomisation option.** A previously-recorded "believed to exist" fake-players toggle **does not exist**. Corrected in PLAN.md and marked as checked. Randomisation now rests on holidaying forward 15–20 seasons. The user also spotted a "real-world fixtures for the first season" option, now adopted for the real-world column as free variance reduction.
4. **Relaunched FM + CE from cold**, attached, loaded the vendored table, enabled Features + Current Player, confirmed the table resolves against entirely new heap addresses (Grealish now at `D0F80E94` vs yesterday's `AFC7E...`) — a genuine restart, which is what the validation needed.
5. **Wrote `scripts/lua/locate_vector.lua`** to re-derive the squad vector header after a restart, since the header is a fresh allocation each launch. Two rounds of fixes, both driven by live failures (below).
6. **Reopened `squadvec_L4.PTR` in the new process** and let CE re-resolve all 27 paths.

## Did it achieve its goals?

Goals were: (1) validate the 27 pointer paths across a restart, (2) find what populates `pCurrentClub`, (3) a cold-read contamination demo.

- **(1) Validation: completed, and the result is negative.** See below. This is a real finding, not a failure to test.
- **(2) `pCurrentClub`: not attempted** — ran out of session on (1).
- **(3) Cold read: not attempted.**

## The negative result

CE re-resolved all 27 paths in the fresh process. Outcome:

- The large majority show `-` — the chain breaks partway and resolves to nothing.
- Several resolve but to obvious garbage: `000009F1`, `00000F90`, and three separate paths landing on `00578C28 = 0`.
- One (`fm.exe+070ACAD0` → `8, 1D0, 0, F0`) resolves to a live heap address `D5896EC0`, but not to anything resembling a `{begin, end, capacity_end}` header.

**No path survived in a usable form.** This is exactly the outcome the previous session's log warned about — a single-snapshot pointer scan finds paths that happen to hold at that instant, and most are coincidence.

**Important confound, stated honestly:** we could not confirm the Villa squad vector even *exists* in this process (see below). If the target structure isn't currently allocated, no path could resolve to it, so this is not clean evidence that all 27 are coincidental. It is clean evidence that **the paths are not usable as-is**, which is the decision-relevant part.

## What did it learn?

- **The per-club `std::vector<Player*>` structure generalises.** While anchored on an Aston Villa player, `locate_vector` returned a valid 28-entry vector — of **Newport County's** squad (23 Newport players plus 5 loanees from other clubs). Good news for eventually enumerating any club; bad news for naive anchor-based location.
- **The run-walk can bridge between arrays.** `runAround` expands while neighbouring slots resolve as players, and adjacent heap allocations frequently do. That's how a Villa anchor produced Newport's vector. **Fix applied:** the located vector must actually *contain* the anchor pointer. With that check the Newport header is correctly rejected.
- **The authoritative vector is not always the longest run**, so all candidate runs must be probed, not just the best. Fix applied.
- **Villa's squad vector could not be located at all this session**, across three attempts with increasing amounts of FM browsing (Squad screen, scrolling, six different player profiles). Anchoring on Heaton gave 39 pointers / 1 run; on Watkins 109 pointers / 3 runs, including a 297-entry block that is clearly a league-wide arena list. Yesterday's success came from a *different* method — scanning for several known players and clustering the hits — not from a single anchor. **Single-anchor location is unreliable and should not be the primary method.**
- **Reopening a `.PTR` in a fresh process is a fast survival test.** CE re-resolves every path on load and shows what each currently points at, so you can read off survivors without needing the target address first. This is much cheaper than the documented "rescan against the new address" flow and doesn't require locating the target at all. Worth reusing.

## What went wrong?

- **Two bugs in `locate_vector.lua`, both shipped and caught live** — probing only the best run, and not checking anchor containment. Both are now fixed, but both were avoidable by thinking about the failure mode first; the previous session had already documented that run-walking over-extends.
- **Burned most of the session on locating the vector**, which was supposed to be the quick prerequisite step, leaving `pCurrentClub` and the cold read untouched.
- **The validation is confounded** by not being able to confirm the target exists, as noted above. It answers "are these paths usable" (no) but not "were they all coincidence" (unknown).
- One earlier `locate_vector` run returned Newport County's squad and was briefly taken at face value before the club column was checked.

---

## Next session should probably

1. **Fix squad-vector location properly before anything else.** Port yesterday's *working* method into a script: probe several known squad members (`probe_watch.lua`), scan for each, and find the array containing the most of them — rather than anchoring on one player. Single-anchor discovery has now failed three times.
2. **Then redo the pointer validation on a confirmed-live target.** With the vector confirmed present, reopening the `.PTR` immediately shows which paths survive. If still none, move to the two-pointermap compare workflow, which is the technique CE's own warning points at.
3. **Consider whether a static path is needed at all.** The scanning approach already produces exact squads via the vector header. A static path is an optimisation, not a blocker — and if it keeps resisting, the cheaper win is a reliable locator plus caching the header for the session.
4. Still outstanding from yesterday: `pCurrentClub`, and fixtures/league tables/shortlist for the Phase 1 exit criterion.
