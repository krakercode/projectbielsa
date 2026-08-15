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
| Heap object address | `975AA370` (Aston Villa) | **No** — fresh allocation every launch |
| CE GUI scan results | the 5,081 found-list | **No** — dies with Cheat Engine too |

Code addresses are the durable asset. Every data address below is a snapshot.

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

## Saves

- Live save: `Documents/Sports Interactive/Football Manager 2021/games/Claude Anthropic - Aston Villa.fm`, saved 2026-08-15 23:29 (4 Oct 2020).
- Backups: `D:\projectbielsa-save-backup\2026-08-15-2323\` (pre-save) and
  `D:\projectbielsa-save-backup\2026-08-16-0035-eod\` (current, includes FM's own
  `last save overwrite backup.fm`).

## Not mine, still uncommitted

`scripts/vision/capture.ps1` — a screen-capture helper for OCR-ing FM's UI,
referencing a `read_screen.js` that does not exist yet. Left untracked
deliberately; it is someone else's unfinished work. Given the 2026-08-16 finding
that the table numbers are never stored as integers, this OCR route is now a
serious contender rather than a fallback.
