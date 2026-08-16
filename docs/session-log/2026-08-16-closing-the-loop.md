# Session Log — 2026-08-16 (closing the decision loop)

## Session metadata

- **Date:** 2026-08-16 (third and largest block of the day)
- **Phase(s) touched:** Phase 2 (write layer completion) and **Phase 4 (the
  orchestration loop — exit criterion met)**
- **Starting point:** `set_lineup()` worked but needed a manually-supplied address
  and a hand-made squad dump; `pick_lineup` decided in isolation and nothing
  joined them. See `docs/session-log/2026-08-16-phase2-lineup-read.md`.
- **Access available this session:** Full desktop. FM was **closed** at the start
  and was relaunched from cold, which turned out to be the best possible test.

## What did it do?

1. **Stepped back and planned.** Wrote out the honest state of all four layers.
   The decisive observation: `pick_lineup` decides, `set_lineup` acts,
   `read_lineup` verifies, and **nothing joined them** — which is precisely
   PLAN.md's Phase 4 exit criterion, one small script away.
2. **`scripts/win/scan_mem.ps1` — multi-pattern.** Many patterns in one pass,
   dispatched on first byte. 23 signatures over 2.4 GB in ~5.5 s, against ~55 s
   for 23 sequential sweeps.
3. **`scripts/manager/read_squad.js` — CE-free live squad read.** ~6 s from cold
   versus ~2 minutes via Cheat Engine, and no manual step at all.
4. **`scripts/manager/tactic.js`** — single source of truth for the tactic.
5. **`scripts/manager/prompts.js`** — scaffold extracted; `pick_lineup` made
   **slot-based**.
6. **`scripts/manager/run_decision.js` — the loop.**
7. Added `--strategy baseline`, availability filtering, and model self-correction.
8. Relaunched FM from cold and loaded the save to test everything against a
   brand-new process.

## Did it achieve its goals?

**Yes — Phase 4's exit criterion is met**, and verified twice:

```
--strategy baseline   9 slots changed -> set_lineup: verified
--strategy oneshot    7 slots changed -> set_lineup: verified, 85.8s
```

Both were confirmed on FM's tactics screen afterwards, not just in memory.

`read_squad.js` was verified against a **fresh fm.exe process** — every heap
address different from the session it was designed in:

- 23 signatures → exactly 23 hits, 23/23 records validated
- **752 immutable fields identical** to the CE dump that was itself verified
  field-by-field against FM's UI, so this is a transitive UI verification
- only 7 immutable fields differ, all legitimate — a position retrain, slow
  personality drift, and two players whose weight was `0` in the old dump and
  reads correctly now
- Grealish correct end to end: club via the 4-level chain, born 1995, CA 163/PA
  170, contract 2020–2025 joined 2011, AMC 20 / AML 19 / MC 20

## Why did it do what it did?

- **Slot-based rather than position-based.** `pick_lineup` returned
  `{id, position}` in FM's position vocabulary while the write layer fills the
  tactic's *slots*. A 4-3-3 has two DC-capable and two MC-capable slots, so any
  bridge between the two has to guess, and a wrong guess silently misplaces
  players. Asking the model to fill the actual slots removes the guess and is
  what a human does anyway.
- **Anchoring on Row ID + UID.** They are **adjacent** (`0x278`, `0x27C`), so
  together they are an 8-byte signature. A bare 4-byte UID returns hundreds of
  coincidental hits; the pair returned exactly one per player.
- **Roster as the anchor.** UIDs, Row IDs, names and position ratings are *game*
  data — identical across restarts, unlike every address in the process.
- **Generic chain following.** Chain depth varies (Contract 1 deref, names 2,
  Team Club 3). Assuming a depth crashed on the deep one.
- **Offsets from `cheat-table/fields.json`, never hand-copied** — hand-copying is
  what produced the reversed-offset bug that nil-ed every name and contract field.

## What did it learn?

- **The selection list does not exist until the Tactics screen has been drawn.**
  In a freshly launched fm.exe, `locate_lineup` found nothing at all; after
  visiting Tactics it found the list immediately. Same class of gotcha as
  `pCurrentClub` needing a club screen. `run_decision.js` therefore navigates to
  Tactics first.
- **A fresh process has NO stale generations.** Right after loading, exactly one
  variant existed and the ambiguity warning did not fire. Staleness accumulates
  with every render.
- **Availability is not the same as the squad.** 23 registered, 19 pickable. The
  live selection list is the availability set.
- **"Fewest remaining differences" identifies the live copy.** Every drag moves
  toward the target, so stale generations are by definition further behind. This
  needs no calibration and cannot be fooled by stale copies outnumbering live
  ones — unlike every earlier attempt.

## What went wrong?

Three real bugs, all found by *running* it rather than reading it — which is the
argument for closing the loop early rather than building more layers first:

1. **The baseline picked an injured player.** No availability filter existed.
2. **A recycled buffer read as "done".** `set_lineup`'s fixpoint loop treated a
   null read identically to an empty plan, so a nine-drag plan stopped silently
   after one drag and reported the remaining eight as fine. The worst kind of
   bug — it looked like success.
3. **Tracking one live copy did not survive contact.** After an action the live
   data can sit in a buffer allocated *after* we located; both located copies went
   stale while the game itself had changed correctly. Replaced with the
   fewest-remaining rule.

Also:
- **My first `read_squad` chain follower crashed** on the 4-level Team Club chain
  because it assumed 2–3 levels.
- **The first loop run took 456 s** because every iteration re-scanned memory.
  Fixed by pointing `locate_lineup` at the multi-pattern scanner and caching the
  candidate list in `set_lineup`; now 86 s.
- **Qwen put the same player in two slots.** Validation refused to apply. Added
  self-correction — it corrected on attempt 2 — and `attempts` is logged so
  "usable on the first try" stays measurable rather than hidden by retries.
- **Left untested:** the `tools` agentic strategy has *still* never run.

---

## Next session should probably

1. **Advance the game.** The agent can pick a team but cannot play. This needs a
   way to detect that time moved — the in-game date is not readable from memory
   yet. Options: scan for the date, OCR it, or watch the next-match opponent
   change. Until this exists no scenario can run, so it is the real frontier.
2. **Exercise the `tools` strategy once.** It is the last untested code path and
   this project has been bitten by exactly that twice.
3. **Analyse cost per decision.** Tokens and wall clock are now logged for every
   decision; PLAN.md says measure this *before* committing to the 2×2 grid.
4. **Note the loop is tied to one tactic.** `tactic.js` describes 4-3-3 DM Wide
   and the formation is not read from the game; that belongs with `set_tactic()`.
