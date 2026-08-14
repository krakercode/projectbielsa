# Session Log — 2026-08-14 (live squad read)

## Session metadata

- **Date:** 2026-08-14
- **Phase(s) touched:** Phase 1 (single-record dump verified and fixed; full-squad read working with a known gap)
- **Starting point:** Phase 0 confirmed passed. `dump_state.lua` existed but had **never been run** — generated from static analysis of `fm.CT` in a session with no desktop access. The squad-array work hadn't started. See `docs/session-log/2026-08-14-phase0-completion-and-phase4-design.md`.
- **Access available this session:** Full live desktop control (computer-use granted by the user, who was at the machine), Cheat Engine attached to a running FM21 save.

## What did it do?

1. Requested and got computer-use access to Cheat Engine, FM21 and File Explorer. Attached CE to `fm.exe` (PID 7468), loaded the vendored `cheat-table/FM21-Cheat-Table/Source/fm.CT`, activated `-----[==Features==]-----` then `Current Player`.
2. Confirmed the table resolves live against a real save (Aston Villa, 27 Jul 2020) — names, birth year, height, value all correct for Jack Grealish.
3. **First-ever live run of `dump_state.lua`.** It ran without erroring but silently dropped every multi-level field. Root-caused to offset ordering (see below), fixed in `cheat-table/parse_ct.js`, regenerated `fields.json` and `scripts/lua/dump_state.lua`. Re-ran: all 106 player fields correct, validated field-by-field against the profile screen. Commit `51d363e`.
4. Established how the squad is actually stored, in stages:
   - `probe_watch.lua` (new) — CE timer logging every player selected; clicked through 8 Villa players in FM in one pass to collect record addresses.
   - Tested and **rejected** the "row-indexed contiguous array" hypothesis: addresses don't track `Row ID` (Martínez's record is 22 MB from the rest).
   - `scan_squad_array.lua` (new) — scanned memory for qwords equal to those 8 addresses (262 hits), clustered them offline; found several arrays holding pointers to all 8 at consistent 8-byte-multiple spacing.
   - `inspect_array.lua` (new) — walked each candidate resolving every slot as a player. Found a 23-run = Villa's senior squad, and 36-runs = the youth teams.
   - `who_points_here.lua` (new) — walked up from the senior array to a `std::vector` header at `0x6B7CC8C0` = `{begin 0x9C3ED6F0, end 0x9C3ED7A8, cap 0x9C3ED7D0}`, i.e. exactly 23 players.
   - `find_club_players.lua` (new) — looked for a player container on the club object (`0x8C7F2220`, Aston Villa). Found nothing in its first 4 KB; abandoned rather than widened, for time.
5. Extended the generator so `dump_state.lua` exposes `dump_player_at(address)`, `FM_FIELDS`, `FM_dumpRecordAt`, `FM_resolveFrom`.
6. Wrote `scripts/lua/dump_squad.lua` and ran it live: 20 Aston Villa players dumped with correct CA/PA/attributes and correct first+last names.
7. Rewrote `docs/phase1-notes.md` with all of the above. Commit `1608f2b`. Both commits pushed to `origin/main`.

Attempted and abandoned: bringing CE forward with `open_application` — it launches a *new* CE instance rather than focusing the running one, and I did this twice before noticing. Alt+Tab and Win+D don't take from FM's fullscreen window either. Settled on a PowerShell `SetForegroundWindow` helper (in the scratchpad, not the repo).

## Did it achieve its goals?

Session goals were: (1) test `dump_state.lua` live and fix what breaks, (2) if that works, do the squad-array scan.

- **(1) Test and fix `dump_state.lua`: yes, fully.** It was broken — silently, in a way static analysis could not have caught — and is now verified field-by-field against the game's own UI, not just "runs without error."
- **(2) Squad array: yes on identification, partially on the dump.** The structure is positively identified (a `std::vector<Player*>`, header located, count arithmetic checked against the real squad size). `dump_squad.lua` works and returns real data, **but returns 20 players where the squad is 23** — it locked onto an arena copy whose neighbouring slots had been overwritten. So: full-squad read demonstrated, not yet exactly right.
- **Phase 1 exit criterion ("one script call produces a clean JSON snapshot of an entire save's key state"): still not met.** One call now produces a whole squad, which is the hard part, but it's the wrong count, and club/competition/fixture state isn't covered at all. Don't mark Phase 1 done.

## Why did it do what it did?

- **Fixed the offset order in `parse_ct.js`, not in `dump_state.lua`.** `dump_state.lua` is generated; hand-patching it would be overwritten by the next regeneration. The reversal is a property of CE's file format, so it belongs in the parser.
- **Did not hardcode `0x6B7CC8C0`.** It's a fresh heap allocation each run — hardcoding it would produce a script that works today and breaks silently on the next launch, which is the same class of bug as the untested code this session had to fix. Locating the array from the live selection costs a memory scan per call but survives restarts.
- **Left the vector-header validation unimplemented.** It's the known fix for 20-vs-23 and I could see how to write it, but I ran out of session to verify it live. Shipping it untested is precisely what caused the offset bug. It's written up in `docs/phase1-notes.md` and in `dump_squad.lua`'s header instead.
- **Stopped widening the club-object search.** A two-level search (club → member object → array) is a large number of memory reads through CE's Lua API and was going to be slow; the selection-anchored approach already worked. Flagged as unfinished rather than pursued.
- **Kept the dump raw.** Attributes are FM's internal 1–100, not the displayed 1–20. Converting in the dump would bake a lossy transform into the data layer; consumers can divide by 5.

## What did it learn?

- **CE stores `<Offsets>` innermost-first — the reverse of application order.** This is the single most important finding. Every single-offset field works either way, so a table can look completely correct while every multi-level chain is silently nil.
- **Player records are individually heap-allocated.** `Row ID` (offset `0x278`) is an index into something else entirely; record addresses have no arithmetic relationship to it.
- **The senior squad is a `std::vector<Player*>`**, and FM keeps additional arena copies of the same pointer set. The arena is shared with unrelated lists — the same region held a Cameroon national squad — so "an array containing this club's players" is not by itself proof of having found the club's own list.
- **Nothing points at the vector header** (zero referrers), so it's embedded by value in its owner. That's the case CE's Pointer Scanner exists for.
- **`Full Name` (`0x2B8`) is a lazily-populated cache** — nil for players FM hasn't rendered. First/Last name are reliable. This looks like a read bug and isn't one.
- **Strings were never the problem.** Last session flagged them as the most likely failure point; `fm.CT` has `Unicode=0` and `readString(addr, n, false)` was already correct.
- **Environment:** `open_application` starts a second Cheat Engine rather than focusing the running one. FM21 runs borderless-fullscreen over the taskbar and doesn't yield to synthetic Alt+Tab or Win+D. Focusing a specific window via PowerShell `SetForegroundWindow` is what actually works.

## What went wrong?

- **`dump_state.lua` was broken on arrival** — the previous session's "strong first draft" produced nil for every name and contract field. The specific prediction about what would break (string encoding) was wrong; the actual cause (offset order) wasn't considered.
- **`dump_squad.lua` returns 20 of 23.** Left in that state deliberately, documented in two places, with the fix written down.
- **Left two stray Cheat Engine processes running** (PIDs 16420 and 18020) from the `open_application` mistake. They have no table loaded and aren't attached to anything; harmless, but they're there.
- **One batch of clicks and typed text went into FM instead of CE** because I didn't re-focus CE first. FM was on a player profile and ignored it — no state changed — but the same mistake on an interactive screen could have clicked something real. Always focus explicitly before driving CE.
- **Declined CE's "Enable CEShare table lookups?" prompt** without asking. It's an online-lookup feature we don't need; if the user wants it on, it's in CE's settings.
- **Staff dumping is untested.** `pCurrentStaff` read 0 all session because no staff member was ever selected. Untested, not known-broken.
- **Open question:** where the club's *own* player list lives, if anywhere reachable from the club object. `find_club_players.lua` came back empty on a 4 KB scan, which is not enough to conclude it isn't there.

---

## Addendum — same session, continued work

The user asked to continue with items 1 and 2 from the list below. Both are done.

**1. Squad count — fixed, but not the way it was planned.** Header validation was implemented as described (`vectorCountFor`), and it **never fired**. The reason matters: `runAround` expands while neighbouring slots resolve as players, and adjacent heap allocations often do hold valid player pointers, so the walked run overshoots the vector's real bounds. The header lookup then scans for a start address that isn't `begin`, finds nothing, and falls back. First run gave 20/23; a second run with a different anchor gave *zero* candidates because the `sameClub` filter demanded unanimity (since relaxed to a 70% majority so one loanee can't veto a squad).

A diagnostic (`scripts/lua/diag_squad.lua`, new) settled it: `0x6B7CC8C0` was **still a valid vector header** after all the navigation — same 23 Villa players. So the vector is a stable data structure, not a per-screen UI list, and the problem was purely the heuristic's bounds. Added `squad_from_vector(header)` and `dump_squad_to_file(path, header)` to read the container directly. **Result: 23/23, zero incomplete records** — every player with first+last name, CA, PA, all attributes, correct club. The scanning path stays as a best-effort fallback.

**2. Staff — verified.** The actual cause of `pCurrentStaff` reading 0 was *not* "no staff member selected", as the main log above guessed. `Current Player`, `Current Club` and `Current Staff` are **three separate hook scripts and each has to be ticked individually** — only `Current Player` had ever been enabled. Enabling one also doesn't backfill; the hook populates its pointer the next time the game touches that record, so you must re-select in FM afterwards.

With that done, all 83 staff fields read correctly for John Terry (Villa coach): birthplace Barking, contract £10K p/w started 2018 expires 2021, CA/PA 110/152, job attributes (Coach 20, Manager 20, Assistant Manager 17, rest 1) matching the role dots on his profile. Staff attributes follow the same `displayed = round(internal/5)` rule — but **Level of Discipline (`0x1C`) and Working with Youngsters (`0x24`) read back already on the 1–20 scale**, as does the whole Personality block. Don't blanket-divide staff attributes by 5.

**Club — attempted, still unverified.** Since the club hook was now enabled, I tried it too (beyond the two requested items). `pCurrentClub` stayed 0 on both the Club Info profile page and the staff pages, so it triggers on something more specific. The 30 club fields remain untested. Didn't chase further.

Also worth recording: the main log above stated staff was "untested, not known-broken" and attributed it to selection. That was wrong — it was a disabled script. Corrected here rather than silently.

## Addendum 2 — pointer scan

Ran CE's Pointer Scanner against `0x6B7CC8C0` (header re-verified live first: `begin=9C3ED6F0 end=9C3ED7A8 count=23`).

- **Level 3 / max offset 1023: zero paths, instantly.** "Unique pointervalues in target: 0" — nothing anywhere points within 1 KB before the header, consistent with it sitting deep inside a large owner object.
- **Level 4 / max offset 4095: 27 paths in under 40 seconds, 16 KB total.** All rooted at static module addresses. Saved to `D:\ptrscan\squadvec_L4.PTR`.

Deliberately started small: CE warns that scanning without a comparison pointermap can produce "billions of useless results and giga/terabytes of wasted diskspace", and C: only has ~21 GB free — hence D: for output, and level 3 before level 4. **This contradicts the previous prediction in this very log that the pointer scan needed its own session for being heavyweight.** It was the cheap part. The expensive part is validation, which is not done.

The 27 collapse into ~6 families (many rows are the same object via a different base+offset split; bases differ by 0x7C/0x80 and the first offset compensates). Two root in `eossdk-win64-shipping` rather than `fm.exe` and are almost certainly coincidence. Full table in `docs/phase1-notes.md`; the `.PTR` is authoritative — reopen it in CE rather than retyping.

**The paths are unvalidated and most are probably wrong.** A single-snapshot scan finds whatever resolves right now. They only become trustworthy after filtering across a game restart, which needs the user's say-so since it restarts their save. Procedure written up in `docs/phase1-notes.md`.

## Session end state

- Repo clean, all work pushed through `d311e6c`.
- `D:\ptrscan\squadvec_L4.PTR` — **not** in the repo (it's a CE binary artifact on another drive). Next session needs it; if it's gone, re-running the scan is under a minute.
- Cheat table scripts were unticked and Cheat Engine closed cleanly, **without saving the table** — the added "squad vector header" entry was scratch, and saving would have modified the vendored `fm.CT`.
- Of the two stray CE processes from the `open_application` mistake, PID 16420 was killed. **PID 18020 could not be** — it's running elevated and `Stop-Process` returns "Access is denied" from a non-elevated shell. It has no window and no table loaded, so it's inert, but it's still there; killing it needs an admin Task Manager. Didn't escalate privileges to force it.
- FM21 was left running with the save loaded, deliberately — quitting a game with a live save risks discarding progress, and that's the user's call, not something to do as cleanup.

---

## Next session should probably

1. **Validate the 27 pointer paths across a restart.** Restart FM and load the save, re-locate the vector header in the new process (`dump_squad.lua` scan → `who_points_here.lua` on the array start), reopen `D:\ptrscan\squadvec_L4.PTR`, then **Pointer scanner → "Rescan memory — removes pointers not pointing to the right address"** with the new address. Repeat over a second restart. Whatever survives becomes the primary resolution path in `dump_squad.lua`. Budget ~30–45 min for one round, ~1 hour to trust it. Note a restart means re-attaching CE, re-enabling all three hook scripts, and re-selecting a player. If nothing survives, the path is longer than 4 levels and the two-pointermap compare workflow is needed instead.
2. **Find what populates `pCurrentClub`.** Try the Finances or Facilities screens, or a club search result, before assuming the script is broken. Club finances block any transfer decision.
3. **Fixtures, league tables and the transfer shortlist** — completely unexplored, and all required by Phase 1's exit criterion.
