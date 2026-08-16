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

## Durable: structural offsets

| Offset | Meaning |
| --- | --- |
| `club + 0xB8` → `+0x4` | club name string (`readString(..., false)`) |
| `BBD9-style record + 0x30` | the record's own club pointer |
| `BBD9-style record + 0x38` | a per-club sub-object (checked, holds no table stats) |

---

## Perishable: the 15–16 Aug session snapshot

**Valid only while `fm.exe` PID 22352 (started 2026-08-15 16:02) keeps running.**
If FM has restarted, every address below is meaningless — delete them from your
working set and re-derive.

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

## Phase 2 tooling (all CE-free, all read-only on memory)

| Script | Purpose |
| --- | --- |
| `scripts/manager/set_lineup.js` | Apply an XI by driving the tactics UI, then verify from memory. Needs no address. |
| `scripts/manager/locate_lineup.js` | Find the selection list from cold, anchored on the roster |
| `scripts/manager/read_lineup.js` | Parse a dumped region into an XI |
| `scripts/win/scan_mem.ps1` | Pattern scan over writable memory — 2.5 GB in ~2.4 s |
| `scripts/win/read_mem.ps1`, `dump_many.ps1` | Read memory; page-tolerant, zero-fill unmapped pages |
| `scripts/win/click.ps1` | Synthetic mouse via `SendInput`; `-Drag` for list-row drags |
| `scripts/win/focus.ps1` | Reliable window focus |

Two UI facts these depend on: FM **accepts synthetic input**, and the swap
dropdown's candidate order is **not stable** — so lineup changes are made by
dragging between list rows, whose positions are fixed.

## Saves

- Live save: `Documents/Sports Interactive/Football Manager 2021/games/Claude Anthropic - Aston Villa.fm`, saved 2026-08-16 12:15 (4 Oct 2020).
- Backups: `D:\projectbielsa-save-backup\` — `2026-08-15-2323\`, `2026-08-16-0035-eod\`,
  and `2026-08-16-1215-phase2\` (most recent).
- The save now has a tactic: **Fluid Counter-Attack / Cautious 4-3-3 DM Wide**,
  created 2026-08-16 because Phase 2 is impossible without one (FM had been
  auto-picking for the four matches played). Current XI ends with Targett at DL
  and Davis at STC, from `set_lineup.js` runs.

## Not mine, still uncommitted

`scripts/vision/capture.ps1` — a screen-capture helper for OCR-ing FM's UI,
referencing a `read_screen.js` that does not exist yet. Left untracked
deliberately; it is someone else's unfinished work. Given the 2026-08-16 finding
that the table numbers are never stored as integers, this OCR route is now a
serious contender rather than a fallback.
