# Session Log — 2026-08-14

## Session metadata

- **Date:** 2026-08-14
- **Phase(s) touched:** Phase 0 (completed), Phase 1 (partial — single-record dump only, squad-array walk still not started), Phase 4 design (new)
- **Starting point:** Repo freshly scaffolded earlier this same session (PLAN.md, docs/, cheat-table/, scripts/ stubs). FM21/Steam/gh confirmed installed; Cheat Engine not yet installed.
- **Access available this session:** Started with none (user installing Cheat Engine). Gained live desktop guidance mid-session via the user manually driving Cheat Engine and sharing screenshots — not direct computer-use control. Lost desktop access entirely partway through (user left the house); computer-use access requests failed outright for the rest of the session ("can't be approved during a scheduled run" — this session was dispatched, not a live interactive chat, so there was never a live human able to click the approval dialog).

## What did it do?

1. Guided the user through installing Cheat Engine and loading `fm.CT`, via screenshots (not direct control) — helped debug a frozen CE window (unrelated New Scan left running) and a collapsed script tree (child entries hidden under `-----[==Features==]-----`, needed expand + activate).
2. Confirmed Phase 0 exit criterion live: CE attached to `fm.exe`, "Current Player" script activated, CA/PA/attributes updated live for a real player (Ezri Konsa, Aston Villa). Updated `docs/phase0-feasibility.md` and `README.md` to mark Phase 0 passed.
3. User then left the house. Attempted to take over Cheat Engine directly via computer-use (`mcp__computer-use__request_access`) to continue Phase 1's squad-array AOB scan — failed every attempt with "can't be approved during a scheduled run," confirmed by the user this session was launched via some kind of "dispatch" mechanism, not manually. This is a hard blocker, not a bug: no live human = no one to approve screen-control.
4. Given no desktop access, built what was possible from static analysis instead: wrote `cheat-table/parse_ct.js` (parses `fm.CT`'s XML into `cheat-table/fields.json` — 106 player / 30 club / 83 staff fields with real pointer-offset chains) and `cheat-table/generate_dump_lua.js` (generates `scripts/lua/dump_state.lua` from that data — a real Lua script with a generic pointer-chain resolver, type-aware reader, and hand-rolled JSON encoder). Committed as `22d4903`.
5. Retried computer-use access twice more after the user said this was a manually-started chat — same failure both times. Concluded (with the user) that "dispatch" launched this specific conversation in a way the platform treats as unattended/scheduled regardless of how it looks from inside the chat.
6. Wrote `docs/control-interface.md` — a Phase 4 design doc for how models actually drive the manager (agentic tool-use loop per decision event, not the flat JSON-in/JSON-out PLAN.md originally sketched; manager-profile config; memory tool for cross-session coherence; model-agnostic adapter shape; decision logging). Grounded against current Claude API tool-use/caching mechanics via the `claude-api` skill before writing it. Committed as `5313df8`.
7. Created `docs/session-log/TEMPLATE.md` and this convention (`CLAUDE.md` pointing to it), per explicit user request.

## Did it achieve its goals?

- **Phase 0 exit criterion ("attach CE, read a known value live"): yes.** Directly confirmed via the user's screenshots — CA/PA/attributes updated live for a real player.
- **Phase 1 exit criterion ("one script call produces a clean JSON snapshot of an entire save's key state"): no, only partially.** `dump_state.lua` can now dump the *currently-selected* player/club/staff in full — real progress — but the actual exit criterion is the full squad in one shot, which needs the squad-array pointer, which needs live AOB scanning that never happened this session. Don't round this up to "Phase 1 done."
- **Taking over live Cheat Engine work directly: no.** Blocked at the platform level (scheduled-run classification), not something retrying or rephrasing fixed.
- **Phase 4 design work: not a stated goal at session start, but a reasonable use of blocked time — produced a real, usable design doc**, not just placeholder text. No code from it yet, by design (still gated on Phase 1/2 read/write existing).

## Why did it do what it did?

- **Chose static analysis (parse the `.CT` XML) over waiting idle once desktop access failed.** The base table's own file already contains every offset the base table exposes for single-record reads — this was extractable without touching Cheat Engine, so it was real, verifiable progress rather than speculative code. Deliberately did *not* attempt to guess at the squad-array pointer or write speculative AOB-scan code, since that genuinely can't be done without live memory access — no amount of static analysis substitutes for it, and pretending otherwise would produce something untested and probably wrong.
- **Generated `dump_state.lua` from a script rather than hand-writing it.** 219 fields across three record types is large enough that manual transcription would introduce errors; the two-step parse→generate approach (`parse_ct.js` → `generate_dump_lua.js`) is also easy to re-run if `fm.CT` changes later, rather than a one-off hand edit that immediately goes stale.
- **Chose an agentic tool-use loop over PLAN.md's literal "JSON-state-in/JSON-decision-out" phrasing for Phase 4.** Reasoning is spelled out in `docs/control-interface.md` itself (token cost of dumping full state every decision, no selective lookup, doesn't match how current agentic models are actually trained to perform) — flagged explicitly as a deviation from the plan's wording rather than silently substituted.
- **Did not keep retrying `request_access` blindly.** After the second identical failure with the user confirming manual setup, further retries wouldn't have told us anything new — the right move was explaining the likely cause (dispatch-launched session) and pivoting to work that didn't need it, not repeatedly hitting the same wall.

## What did it learn?

- **`fm.CT`'s own README states it was tested against CE 7.2 and FM21 v21.3**, not the 7.2/v21.4.0 pairing PLAN.md originally assumed — noted in `cheat-table/README.md`, not yet actually causing a problem (Phase 0 worked fine on whatever version this machine has), but worth remembering if pointers ever look wrong.
- **CE's "-----[==Features==]-----" style headers with `moHideChildren="1"` hide child scripts behind a collapse arrow** — easy to mistake for "the table failed to load" when it's just collapsed. Also: those parent script entries must be *activated* (ticked), not just expanded, since they allocate the memory (`pCurrentPlayer` etc.) the child scripts read from.
- **CE's pointer-offset chain semantics** (confirmed by reading `fm.CT`'s own XML, not guessed): for offsets `[O1, O2, ..., On]` on a base symbol, resolve as `addr = [symbol] + O1`, then for each subsequent offset `addr = [addr] + Oi` (dereference-then-add), with the *last* computed address read directly (no final dereference). This is now encoded in `dump_state.lua`'s `resolvePointerChain`.
- **Computer-use access approval is fundamentally unavailable in a dispatched/unattended session**, confirmed as a deliberate platform safety boundary (no live human to click "allow" = no grant), not a bug and not something a fresh session or rephrased request works around. Worth remembering before promising "I'll take over" in any future unattended context.
- **This machine's Steam library setup**: FM21 lives in `D:\SteamLibrary`, not the default `C:\Program Files (x86)\Steam` library — worth remembering if any future session needs to locate install files directly.

## What went wrong?

- **`dump_state.lua` remains completely untested against the live game.** It was generated carefully and the offset-chain logic was verified by reading `fm.CT`'s own resolution semantics (not guessed), but no live CE session was available this session to actually run `dump_state_json()` and see real output. Flagged explicitly at the top of the generated file and in `docs/phase1-notes.md`. The single most likely failure point: the "String" field type (player/club names) — 2-3 levels of pointer indirection, and no confirmation yet on whether FM stores those as plain ASCII/UTF-8 or something else (length-prefixed, wide-char).
- **The squad-array AOB scan (the actual Phase 1 exit criterion) never started.** Blocked entirely on live access. `docs/phase1-notes.md` has the scan plan written up, but it's unexecuted.
- **Wasted a couple of tool calls on `request_access` retries** after the first failure already showed the deterministic "retrying returns this same result" message — should have gone straight to explaining/pivoting after the first clear failure rather than trying twice more before the user's clarification made the cause obvious.
- **No actual verification that `readString`/`readSmallInteger`/etc. are the correct Cheat Engine Lua API function names** — they're written from general knowledge of the CE Lua API, not confirmed against this specific CE version's documentation or a live console. If they're wrong, `dump_state.lua` will error loudly (wrapped in `pcall`, so it degrades to `nil` fields rather than crashing) but this hasn't been checked.

## Next session should probably

1. If live access is available: load `dump_state.lua` in CE's Lua Engine (Ctrl+Alt+L) and run `dump_state_json()` against a real selected player — this is the first real test the script has ever had. Fix whatever breaks, starting with the String fields.
2. If live access is available and the dump script works: move on to the squad-array AOB scan per `docs/phase1-notes.md`'s plan (find 2-3 known player addresses via `pPlayer`, scan for those pointer values in memory, look for the backing array).
3. If no live access (another dispatched/unattended session): more design work is reasonable (Phase 2 write-layer schemas, Phase 5 masking-logic research) but don't re-attempt computer-use access — it won't work in that context, confirmed this session.
