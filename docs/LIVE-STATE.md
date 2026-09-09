# Live process state — what survives a restart and what doesn't

Written 2026-08-16 at the end of the debugger sessions. **This file exists because
almost everything found on 15–16 Aug is a heap address that dies the moment
`fm.exe` restarts.** Sessions start cold, so without this the next one either
re-derives it all or, worse, trusts a stale address and gets garbage.

Read this before using ANY hex address from
`docs/session-log/2026-08-15-debugger-league-table.md` or
`docs/session-log/2026-08-16-table-render-loop.md`.

---

## Rule of thumb

| Kind | Example | Survives FM restart? |
| --- | --- | --- |
| `fm.exe+OFFSET` code address | `1455A87E3` | **Yes** — module-relative, stable |
| **Game data** (UIDs, names, position ratings) | `data/roster/*.json` | **Yes** — it is save data, not process data |
| Heap object address | `975AA370` (Aston Villa) | **No** — fresh allocation every launch |
| CE GUI scan results | the 5,081 found-list | **No** — dies with Cheat Engine too |

Code addresses and game data are the durable assets. Every data address below is
a snapshot.

### Worse than "perishable": some buffers are recycled within seconds

Learned the hard way 2026-08-16. The team-selection list is a transient render
buffer, not a stable allocation:

- A selection-list base found earlier the same day no longer parsed at all, with
  **no restart** in between.
- One base was freed and **reused to hold Leicester's squad** between a drag and
  the verification read a second later. It parsed perfectly and reported a
  completely wrong XI.

So **never cache a selection-list address**, and **always validate what you read**
against the roster — if a parsed entry is not one of our players, the buffer is no
longer ours. `scripts/manager/set_lineup.js` does both; copy that pattern.

Use `scripts/manager/locate_lineup.js` to find it fresh. It anchors on UIDs and
names from `data/roster/`, so it needs no prior address.

**And note liveness is not readable.** FM keeps many copies and stale generations
survive — measured 23 stale copies against 21 live, so majority picks the *wrong*
answer. The live copy can only be identified behaviourally: it is the one that
changes when the lineup changes. `set_lineup.js` resolves this by using its own
first drag as the calibration.

---

## Durable: code addresses (still valid after any restart)

| Address | What it is |
| --- | --- |
| `fm.exe+1455A87E3` | **The league-table render loop.** `RBX` = club object, visited in exact table order 1st→20th, constant `RSP`. This is how league position is read. |
| `fm.exe+1440BCF1D` | Club-name render path. `RBX` = club, `RAX` = its name pointer. Fires once per club; during a table render it walks all 20 **alphabetically**. |
| `fm.exe+1440DB515` | **Not useful** — a generic name-formatting helper, ~12,600 hits per navigation. Recorded so nobody breaks here again. |

Return chain observed from `1440BCF1D`: `1440DB515` → `1440BE24A` → `1455A87E3`.

### Durable RTTI / vtable anchors found 2026-09-09

These are module-relative addresses in the current FM21 executable, so they are
restart-safe in the same way as the code offsets above. They identify **classes**,
not the one authoritative live object.

| Vtable offset | RTTI class | Use |
| --- | --- | --- |
| `fm.exe+0x67A4D58`, `+0x67A4EA8`, `+0x67A4EE8` | `CURRENT_GAME_DATE_WIDGET` | Route into the UI date object graph; date is not inline in the widget. |
| `fm.exe+0x68ACAF8`, `+0x68ACB18`, `+0x68ACC10` | `SI_DATE_TYPED_TRAITS@fmdate` | Date infrastructure / typed traits. |
| `fm.exe+0x68A2AE0`, `+0x68A2C30`, `+0x68A2C70` | `MATCH_SCORE_TIME_PANEL@fmmatchviewer` | Strong match-clock target once a live match exists. |
| `fm.exe+0x6494A30` | `GAME_MATCH` | Match object family target. |
| `fm.exe+0x6882188` | `MATCH@simatch` | Match simulation object family target. |
| `fm.exe+0x657B5B0` | `GAME_MATCH_SESSION` | Match-session target. |
| `fm.exe+0x68970A0` | `MATCH_SESSION@fmmatchviewer` | Viewer/session target. |
| `fm.exe+0x690BE28` | `GAME_TEAM_COMP_STATS` | **False clock lead.** Do not interpret its apparent 21/15 fields as time. |

Use `scripts/win/rtti.ps1` to prove a live vtable's class before assigning meaning
to nearby values. Matching integers alone are not enough.

## Durable: structural offsets

| Offset | Meaning |
| --- | --- |
| `club + 0xB8` → `+0x4` | club name string (`readString(..., false)`) |
| `BBD9-style record + 0x30` | the record's own club pointer |
| `BBD9-style record + 0x38` | a per-club sub-object (checked, holds no table stats) |

---

## Perishable: the 15–16 Aug session snapshot

> **STALE AS OF 2026-08-16 16:00.** FM was closed and relaunched (it is now a
> different process with a completely different heap), so **every heap address in
> this section is dead.** They are kept only as a worked example of the record
> layouts. Nothing in the current tooling needs them: `read_squad.js` and
> `locate_lineup.js` both find what they need from cold, anchored on
> `data/roster/`. This is the point of the durable/perishable split.

Aston Villa save, 4 Oct 2020, ~4 match days in.

### The 20 Premier League club objects

Also duplicated in `scripts/lua/find_competition.lua`.

```
Arsenal        975AA208    Leicester      975B0478
Aston Villa    975AA370    Liverpool      975B08B0
Brighton       975AB888    Man City       975B0CE8
Burnley        975ABE28    Man Utd        975B0E50
Chelsea        975AC968    Newcastle      975B1990
Crystal Palace 975ADA48    Sheff Utd      975B35B0
Everton        975AE420    Southampton    975B3CB8
Fulham         975AE9C0    Tottenham      975B51D0
Leeds          975B01A8    West Brom      975B58D8
                           West Ham       975B5A40
                           Wolves         975B6148
```

### Per-club competition records (`BBD9`)

In `scripts/lua/find_row_array.lua` and `dump_league_rows.lua`. `+0x30` is the
club pointer. **Checked to 8 KB: holds no table stats.**

### Other live state

- Squad vector header: **not cached this session** — use `locate_vector()`.
- CE found-list of 5,081 addresses: still loaded in the CE GUI, survived the day.
  Dies if Cheat Engine is closed. Only needed for the "next-scan for 5" approach,
  which is deprioritised.
- CE's debugger is **still attached** to fm.exe. All breakpoints were removed.

---

## If FM has restarted, re-derive in this order

1. Attach CE, load the vendored table, tick **Current Player / Current Club /
   Current Staff** individually, then re-select each entity in FM (enabling a hook
   does not backfill).
2. Club addresses: visit a club screen, read `pCurrentClub`, or run
   `scripts/lua/probe_club_anchor.lua` which reports a live anchor.
3. The 20 PL club objects: arm `scripts/lua/watch_table_render.lua` on
   `fm.exe+1440BCF1D`, navigate to the league table, and read them off the
   alphabetical run.
4. League position: arm `scripts/lua/watch_render_caller.lua` on
   `fm.exe+1455A87E3` with the filter on, navigate to the table, read the ranked
   `RBX` sequence.
5. Squad: `scripts/lua/locate_vector.lua` → `locate_vector()`.

Steps 3 and 4 need no prior addresses — they bootstrap from the code addresses,
which is exactly why those are the durable asset.

---

## Durable: authoritative game-time progress signal

A restart-safe global in this FM21 build is **`fm.exe+0x7002EC8`**. It points
to a live object whose vtable resolves through RTTI to **`GAME`**. The current
observed vtable is `fm.exe+0x6531AA0`; the reader accepts the three GAME
vtables identified in this build and fails closed on anything else.

The values at `GAME+0x90`, `+0x94`, and `+0x98` move with FM's visible
clock and are used together as an opaque fingerprint. **Do not decode or order
them numerically.** The observed encoding is non-monotonic. The only verified
operation is equality/change detection. Live observations:

- 4 Oct 2020 21:15: `07E4591D:07E45916:07E48516`
- 5 Oct 2020 08:00: `07E47D1D:07E47D16:07E48516`
- 5 Oct 2020 09:00: `07E4131E:07E41317:07E48516`
- 5 Oct 2020 15:15: `07E41B1E:07E41B17:07E45D17`

`scripts/win/read_game_time.ps1 -AsJson` follows the static global, validates
the GAME vtable, and returns this fingerprint without memory writes.
`scripts/manager/advance_until_progress.js` clicks only FM's fixed top-right
navigation control until that fingerprint changes. A MUST RESPOND screen is a
safe stop: the script does not click response buttons, and returns no-progress.

### Required-response RTTI index and live press-response path

`scripts/win/rtti_index.js` parses MSVC RTTI directly from the on-disk `fm.exe`
and maps semantic class-name families to durable vtable RVAs. It now also emits
the MSVC CompleteObjectLocator `object_offset` / `cd_offset`, which lets a
reader distinguish the primary vtable (`object_offset == 0`) from secondary
base-class vtables without relying on one process's heap layout. On this build,
`--contains RESPONSE` yields **352 vtables**.

`scripts/manager/find_responses.js` turns that static index into one live scan
of writable FM memory. Raw presence is not enough — stale generations survive —
so current interaction objects must still be isolated by lifetime/differential
behaviour. In the Leicester pre-match press conference this exposed the current
`INTERACTION_GROUPED_RESPONSE_SELECTOR_PANEL` / response-widget generation.

The decoded press-response path is:
`INTERACTION_RESPONSE_WIDGET` primary vtable → widget `+0x1A0` BUTTON →
BUTTON `+0x1B0` text handle → UTF-8 text at `handle+4`. Widget floats at
`+0x5C/+0x60/+0x64/+0x68` are x/y/width/height. `read_press_choices.js`
validates the primary widget and BUTTON vtables, reads all choices, sorts by x,
and returns text plus safe centre-click coordinates.

`PRESS_CONFERENCE_EDIT_SESSION` owns the semantic conference state. Its question
vector is dynamic: FM inserted a follow-up during the live run. While a question
is active, the object at `questions[+0xE0 progress counter]` matched the current
`PRESS_CONFERENCE_QUESTION`. Do **not** treat that as a lifetime invariant: after
the conference finished the counter was 10 while the vector contained 9 questions.
The edit-session object also remained allocated after exit. `read_press_state.js`
therefore exposes a current question only when the counter is inside the vector.

A critical safety rule follows from this: stale `INTERACTION_RESPONSE_WIDGET`
objects can remain plausible after the last question. `run_press_conference.js`
never reads or clicks response choices unless `read_press_state.js` reports a
non-null current question. This guard prevented the controller from replaying stale
answers at terminal state.

Terminal press controls use the same memory-first write pattern. A generic
`read_ui_buttons.js` reader validates primary BUTTON / ICON_BUTTON vtables and
reads their `+0x1B0` text handles plus geometry. It located **Continue To Summary**
as a BUTTON and **Leave Press Conference** as an ICON_BUTTON. The latter was
clicked from its memory-derived rectangle; exit was verified by disappearance of
the live summary panel/button.

The remaining semantic gap is the formatted current-question text. The question
pointer, ID, journalist, media source, dynamic vector membership and answer choices
are all readable, but the formatted question is still assembled through an
unresolved string/template path. For safety, `run_press_conference.js` refuses
choice-only model decisions by default; `--allow-choice-only` exists only to
reproduce the disposable reverse-engineering run. Screenshots remain validation-only.

---

## Perishable: 2026-09-09 game-date investigation snapshot

The live `CURRENT_GAME_DATE_WIDGET` object was observed around `0x8F6EC460` in
this process. **That is a heap address and must not be reused after a restart.**
The durable part is the widget's module-relative vtable anchors above.

A 4 Oct 2020 scan found 1,934 copies of the candidate value `0x07E45916`.
Those contexts were reduced to 49 nearby FM vtable families and then RTTI-
classified. Most were historical/results/UI objects; the decisive family was
`GAME`. That led to the durable global and verified progress fingerprint above.

Keep this section as historical warning: value scans alone are not authority.
The first attractive 21/15 match was `GAME_TEAM_COMP_STATS`, not a clock.

---

## The tooling (all CE-free, all read-only on memory)

**Nothing below needs a hardcoded address.** Everything anchors on
`data/roster/*.json` — UIDs, Row IDs, names and position ratings, which are game
data and identical across restarts.

| Script | Purpose |
| --- | --- |
| `scripts/manager/run_decision.js` | **The loop**: read live → decide → apply → verify → log |
| `scripts/manager/advance_until_progress.js` | Click only top-right navigation until authoritative GAME time moves; stops safely on MUST RESPOND |
| `scripts/manager/find_responses.js` | Build RESPONSE vtable set from RTTI and scan live writable memory for instances |
| `scripts/manager/read_press_choices.js` | Read live press-conference choice text + button geometry from memory; no screenshot input |
| `scripts/manager/read_press_state.js` | Resolve live edit-session progress, dynamic question vector and current question |
| `scripts/manager/run_press_conference.js` | Experimental guarded press controller; refuses choice-only decisions unless explicitly enabled for RE |
| `scripts/manager/read_ui_buttons.js` | Read visible BUTTON / ICON_BUTTON labels + geometry from memory for terminal UI actions |
| `scripts/manager/read_squad.js` | Live squad read, ~6 s from cold, no Cheat Engine |
| `scripts/manager/pick_lineup.js` | The decision event; `--strategy baseline` is model-free |
| `scripts/manager/set_lineup.js` | Apply an XI by driving the tactics UI, then verify |
| `scripts/manager/locate_lineup.js` | Find the selection list from cold (~13 s) |
| `scripts/manager/tactic.js` | Slot names/order/geometry — single source of truth |
| `scripts/manager/prompts.js` | Prompt scaffolds per decision event |
| `scripts/win/scan_mem.ps1` | Multi-pattern scan over writable memory — 2.4 GB in ~5.5 s |
| `scripts/win/rtti.ps1` | Resolve a live FM vtable pointer to its MSVC RTTI class name; read-only. |
| `scripts/win/rtti_index.js` | Parse on-disk fm.exe RTTI into semantic class/vtable sets, including primary/secondary object offsets; `--contains RESPONSE` finds 352 response-family vtables |
| `scripts/win/read_game_time.ps1` | Follow the static GAME root and return the validated live progress fingerprint |
| `scripts/win/read_mem.ps1`, `dump_many.ps1` | Read memory; page-tolerant, zero-fill unmapped |
| `scripts/win/walk_ptrs.ps1` | Read-only bounded pointer-graph exploration helper for opaque live FM objects |
| `scripts/win/click.ps1` | Synthetic mouse via `SendInput`; `-Drag` for list-row drags |
| `scripts/win/focus.ps1` | Reliable window focus |

Facts these depend on, all learned the hard way:

- FM **accepts synthetic input** (`SendInput`).
- The swap dropdown's candidate order is **not stable**, so lineup changes are
  made by **dragging between list rows**, whose positions are fixed.
- **The selection list does not exist until the Tactics screen has been drawn.**
  In a freshly launched fm.exe, `locate_lineup` finds nothing; visit Tactics
  first. `run_decision.js` does this automatically.
- **A squad read returns all 23 registered players; only ~19 are pickable.** The
  live selection list is the availability set.
- **Which copy is live cannot be read** — stale generations survive and can
  outnumber live ones. The rule that works: every drag moves toward the target,
  so the live copy is whichever has the **fewest remaining differences**.
- **Row ID (`0x278`) and UID (`0x27C`) are adjacent**, so together they are an
  8-byte signature that finds a player record with no false positives.

### Quick start after a restart

```bash
node scripts/manager/run_decision.js --strategy baseline --dry-run   # decide, don't act
node scripts/manager/run_decision.js --mode cheat                    # full lineup loop, Qwen
node scripts/manager/advance_until_progress.js                       # advance until time moves or FM requires a decision
```
Needs FM running with the save loaded, and `ollama serve` for the model paths
(`C:\Users\User\AppData\Local\Programs\Ollama\ollama.exe` — it is **not** on PATH).

## Saves

- Live save on disk: `Documents/Sports Interactive/Football Manager 2021/games/Claude Anthropic - Aston Villa.fm`, saved 2026-08-16 16:29 at 4 Oct 2020. The current **running process** was advanced during the 2026-09-09 investigation to at least 16 Oct 2020 12:15 and has completed/exited the Leicester pre-match press conference; that live progress has not been claimed as a new disk-save baseline. During this disposable live run, Qwen negotiated and then accepted a Watford offer for Aaron Ramsey, and FM completed the transfer.
- Backups: `D:\projectbielsa-save-backup\` — `2026-08-15-2323\`,
  `2026-08-16-0035-eod\`, `2026-08-16-1215-phase2\`, and
  `2026-08-16-1629-loop-working\` (most recent).
- The save has a tactic: **Fluid Counter-Attack / Cautious 4-3-3 DM Wide**,
  created 2026-08-16 because Phase 2 is impossible without one (FM had been
  auto-picking for the four matches played).
- The XI on disk is **Qwen's**, from the last `run_decision.js` run: Martínez,
  Cash, Konsa, Mings, Targett, McGinn, Sanson, Nakamba, Traoré, El Ghazi,
  Watkins. Not a result — just the last thing the loop applied.

## Not mine, still uncommitted

`scripts/vision/capture.ps1` — a screen-capture helper for OCR-ing FM's UI,
referencing a `read_screen.js` that does not exist yet. Left untracked
deliberately; it is someone else's unfinished work. Given the 2026-08-16 finding
that the table numbers are never stored as integers, this OCR route is now a
serious contender rather than a fallback.
