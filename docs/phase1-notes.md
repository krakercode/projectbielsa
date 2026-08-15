# Phase 1 — Progress Notes

Status as of 2026-08-14 (first session with live Cheat Engine control).

## Single-record dump: working and verified

`scripts/lua/dump_state.lua` reads every field the vendored `fm.CT` exposes for
the currently-selected player, club and staff member, and serializes to JSON.

It is **generated, not hand-written**, from the table's own data:

1. `cheat-table/parse_ct.js` — parses `fm.CT`'s XML into `cheat-table/fields.json`
   (106 player / 30 club / 83 staff fields).
2. `cheat-table/generate_dump_lua.js` — turns that into `scripts/lua/dump_state.lua`.

Regenerate with `node cheat-table/parse_ct.js && node cheat-table/generate_dump_lua.js`.

Verified live against a real save (Aston Villa, 27 Jul 2020) with Jack Grealish
selected: name, nationality, club, birth year, height, weight, value, wage,
contract years and all 36 visible attributes match the profile screen exactly.

### The bug that mattered: offset order

Cheat Engine stores `<Offsets>` **innermost-first**, the reverse of the order
they're applied. For "Wage Per Week" the table lists `[18, 338]`, but the real
chain is `[[pCurrentPlayer] + 338] + 18` — `338` finds the contract object on
the player, `18` is the wage field inside it.

The parser was emitting them as written, so **every multi-level chain resolved
to garbage and read back nil** — all name fields, all contract fields. Every
single-offset field (CA/PA, attributes, positions, personality) worked fine,
because reversing a one-element list is a no-op. That's why it looked correct
on paper. Fixed in `parse_ct.js`.

Resolution semantics, now confirmed against live memory: for offsets
`[o1..on]` in application order, `addr = [symbol] + o1`, then
`addr = [addr] + oi` for each subsequent offset, reading the final address
directly with no trailing dereference.

### Things that turned out not to be problems

- **Strings.** Flagged last session as the most likely failure point. They were
  already correct: `fm.CT` has `Unicode=0`, so they're plain single-byte
  zero-terminated buffers and `readString(addr, n, false)` is right.
- **CE Lua API names.** `readString` / `readSmallInteger` / `readInteger` /
  `readQword` / `readFloat` / `readBytes` all exist and behave as assumed.

### Value scales (raw, deliberately not converted)

- Attributes: internal 1–100, `displayed = internal / 5`. Grealish's Dribbling
  is 85 internally, 17 on screen.
- CA / PA: native 1–200, no conversion.
- Condition, Fitness, and the reputation fields: 0–10000.
- `Jadedness` reads as a large unsigned number (65411). The base table shows the
  same thing (`ShowAsSigned=0`), so this is inherited from `fm.CT`, not our bug.
  Probably wants signed interpretation.
- `Full Name` (the `0x2B8` chain) is a lazily-populated cache — nil for players
  FM hasn't rendered a full name for. First and Last name are reliable.

## Full-squad read: working

`scripts/lua/dump_squad.lua` dumps a whole squad, not just the selection. It has
two entry points:

```lua
dump_squad_to_file(nil, "6B7CC8C0")  -- exact: read a known vector header
dump_squad_to_file()                 -- heuristic: locate the array by scanning
```

**The vector-header path is exact and verified: 23/23 Aston Villa players, every
record complete — first and last name, CA, PA, all attributes, correct club.**
That's the full senior squad, matching the squad screen.

The vector is also **stable across UI navigation** — re-read after moving
between the squad list, player profiles and staff pages, `0x6B7CC8C0` still held
`{begin, end, cap}` describing the same 23 players. It's a real data structure,
not a per-screen UI list.

### How the squad is actually stored

Player records are **individually heap-allocated**, not a contiguous
row-indexed array — the `Row ID` field is an index into something else, and
addresses don't track it (Martínez's record sits 22 MB from the rest of the
squad). So the squad is an array *of pointers*.

Scanning for qwords equal to known player-record addresses and clustering the
hits found several such arrays. Walking up from one of them:

```
0x6B7CC8C0   std::vector header
  +0x00  begin        = 0x9C3ED6F0
  +0x08  end          = 0x9C3ED7A8   -> (end-begin)/8 = 23 players
  +0x10  capacity_end = 0x9C3ED7D0   -> capacity 28
```

23 is exactly Villa's senior squad. So: **the senior squad is a
`std::vector<Player*>`**, and FM additionally keeps several arena copies of the
same pointers (the youth teams show up as a separate 36-entry run; the same
arena also holds unrelated lists such as a national squad).

### Why there's no hardcoded address

Nothing in memory points *at* `0x6B7CC8C0` — a scan for references returned
zero hits — so the vector header is embedded by value inside its owning object.
There's no pointer path to it yet, and it's a fresh heap allocation every run.

`dump_squad.lua` therefore locates the array from the live selection each time:
take `pCurrentPlayer`, scan for pointers to that record, expand around each hit
while neighbours also resolve as player records, and keep the longest run whose
members all play for the same club. Costs one memory scan per call (a few
seconds), needs no hardcoded addresses, and survives restarts.

### Why the scanning path is still only approximate

Header validation *is* implemented (`vectorCountFor`), but in testing it never
fired, and the reason is worth knowing before someone tries to "fix" it again:

`runAround` expands while neighbouring slots resolve as players, and adjacent
heap allocations often *do* hold valid player pointers. So the walked run
frequently extends past the vector's real bounds. The header lookup then scans
for a start address that isn't the vector's `begin`, finds nothing, and falls
back. On one run it produced 20 of 23; on another, with a different anchor, the
club filter rejected everything and it produced no candidates at all (since
relaxed from unanimous to a 70% majority, so one loanee can't veto a squad).

Making the scanning path exact means solving "which of these slots is `begin`"
without knowing it in advance — several scans per candidate. Given the
vector-header path is already exact, **the better investment is a static pointer
path to the header** (below) rather than more heuristics.

Use `dump_squad_to_file(nil, "<header>")` when you know the header address, and
treat the no-argument form as a best-effort fallback.

## Tooling added this session

All are dev helpers, run from CE's Lua Engine (Ctrl+Alt+L) via
`dofile([[<repo>\scripts\lua\<name>.lua]])`:

| Script | Purpose |
| --- | --- |
| `run_dump.lua` | Load `dump_state.lua`, dump the selection to JSON + a status log on disk |
| `probe_player.lua` | Append the selected player's record address and identity to `probe.jsonl` |
| `probe_watch.lua` | Timer that logs every player selected — click through a squad in one pass |
| `scan_squad_array.lua` | Scan for qwords equal to known player addresses (who points to them) |
| `inspect_array.lua` | Walk a suspected pointer array, resolving each slot as a player |
| `find_club_players.lua` | Look for a player container hanging off the club object |
| `who_points_here.lua` | Generic "who references this address", with neighbouring qwords for context |
| `dump_squad.lua` | The actual squad dump |

`dump_state.lua` now also exposes `dump_player_at(address)`, `FM_FIELDS`,
`FM_dumpRecordAt` and `FM_resolveFrom` so squad-walking code reuses the
generated field tables instead of duplicating offsets.

## Staff: working and verified

**The `Current Player`, `Current Club` and `Current Staff` scripts are three
separate hooks and each must be ticked individually.** `pCurrentStaff` and
`pCurrentClub` read 0 for an entire session not because nothing was selected but
because only `Current Player` had been enabled. Enabling a script also doesn't
backfill — the hook only populates its pointer the next time the game touches
that record, so re-select the entity in FM after ticking the box.

With `Current Staff` enabled and John Terry (Villa coach) selected, all 83 staff
fields read back correctly: name, birthplace (Barking), nationality, contract
(£10K p/w, started 2018, expires 2021), CA/PA 110/152, and the job-attribute
block (Coach 20, Manager 20, Assistant Manager 17, everything else 1) matching
the green/red role dots on his profile.

Staff attributes follow the same `displayed = round(internal / 5)` rule as
players — Determination 88→18, Tactical Knowledge 67→13, Man Management 58→12,
Judging Staff Ability 18→4.

Two exceptions read back already on the 1–20 scale: **Level of Discipline**
(`0x1C`) and **Working with Youngsters** (`0x24`), both matching the displayed
value exactly rather than 5×. The Personality block (Loyalty, Adaptability,
Professionalism…) is also natively 1–20. Don't blanket-divide staff attributes
by 5.

## Club: working and verified

**All 30 club fields read correctly.** Verified live 2026-08-15 against
Liverpool's club page: name and nickname ("The Reds"), stadium Anfield, year
built 1884, capacity 54,074 — all matching the UI — plus facilities (Training
20, Youth 19) and finances (£153,128,037 balance, £17m transfer budget,
£2,969,099 weekly wage budget).

Getting `pCurrentClub` to populate needs **both**:

1. The `Current Club` script ticked (a separate hook from `Current Player`), and
2. **a club screen actually visited afterwards.** Enabling the script does not
   backfill. On 2026-08-14 it read 0 all session because the Club Info page had
   been opened *before* the hook was live.

`scripts/lua/watch_pointers.lua` was written to settle this — it polls all three
`pCurrent*` globals on a timer and logs every transition, so you can browse FM
freely and afterwards see exactly what populated when. Reuse it for any future
"which screen triggers this hook" question.

### The hook retargets to whichever club you view

This is more useful than it first appears. Opening Liverpool's page pointed
`pCurrentClub` at Liverpool, not at our own club:

```
[tick 136] pCurrentClub: 0 -> 975AA370 (Aston Villa)
[tick 339] pCurrentClub: ...    -> 975B08B0 (Liverpool)
```

So **any club's finances, facilities and stadium data are readable by navigating
to that club.** Combined with `locate_vector()` finding any club's squad vector
(proven accidentally when it returned Newport County's), the read layer can
cover opposition clubs, not just our own — which matters for scouting and
transfer reasoning later.

`pCurrentStaff` populated at the same moment, pointing at the manager.

## Pointer scan: 27 candidate static paths (unvalidated)

Ran CE's Pointer Scanner against the squad vector header `0x6B7CC8C0`.

**Level 3 / max offset 1023: zero results, instantly** — "unique pointervalues
in target: 0", meaning nothing anywhere points within 1 KB *before* the header.
Consistent with it being embedded deep inside a large owner object.

**Level 4 / max offset 4095: 27 paths, under 40 seconds, 16 KB of output.** All
root at static module addresses. Saved to `D:\ptrscan\squadvec_L4.PTR` (kept off
C:, which only has ~21 GB free; the `.PTR` is the authoritative record — reopen
it in CE rather than retyping these).

CE warns that scanning without a comparison pointermap can yield "billions of
useless results and giga/terabytes of wasted diskspace". At level 4 / 4095 that
did not materialise, but don't raise the level much without the compare
workflow.

The 27 collapse into a few families (several rows are the same object reached
via a different base+offset split — the bases differ by 0x7C/0x80 and the first
offset compensates):

| Base | Offsets |
| --- | --- |
| `fm.exe+06E62FC8` / `+06E6304C` / `+06E630C8` | `A28/A00/9D8`, `48`, `C30` |
| `fm.exe+06E62FC8` / `+06E6304C` / `+06E630C8` | `A30/A08/9E0`, `48`, `198`, `9F0` |
| `fm.exe+060C2F38` / `+060C2F88` / `+060C2FB0` | `1C`, `224`/`22C`, `48`, `9F0` |
| `fm.exe+07006C90` | `0`, `2D8`/`2E0`, `60`, `B10` |
| `fm.exe+070ACAD0` | `8`, `218`, `48`, `B10` |
| `fm.exe+070B0FC8` | `18`, `F80`/`F88`, `78`, `9F0` |

Two paths root in `eossdk-win64-shipping` (the Epic SDK) rather than `fm.exe` —
almost certainly coincidental and should be discarded first.

### VALIDATED 2026-08-15: none of the 27 survive a restart

Relaunched FM from cold, re-located the squad vector in the new process
(header `53C19A0`, verified by dumping the correct 23 Villa players), then
reopened `squadvec_L4.PTR` and let CE re-resolve every path. Result:

- most break partway and show `-`
- several resolve to garbage — `000009F1`, `00000F90`, three separate paths on `00578C28 = 0`
- one (`fm.exe+070ACAD0` → `8, 1D0, 0, F0`) resolves to a live heap address, but not a header
- **none resolves to `53C19A0`**

The check was run *after* confirming the target was live in the process, so this
is not the "maybe the structure isn't allocated" confound — it's a clean
negative. A single-snapshot level-4 scan yielded no usable static path.

**Useful technique:** reopening a `.PTR` in a fresh process is itself the
survival test. CE re-resolves every path on load and shows what each points at,
so you can read survivors straight off the list. No need to locate the target
first, and much cheaper than the documented rescan-against-new-address flow.

If a static path is wanted, the next escalation is the two-pointermap compare
workflow (generate a pointermap now, restart, generate another, scan with
"compare results with other saved pointermap(s)"), which is what CE's own
warning points at. **But see "Do we even need a static path?" below.**

## Locating the vector after a restart: `locate_vector.lua`

**This is the working procedure. It reproduces across restarts.**

```lua
dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\locate_vector.lua]])
locate_vector()                        -- prints the header address
dump_squad_to_file(nil, "<header>")    -- exact squad
```

Verified live 2026-08-15 from a cold launch: located header `53C19A0` and dumped
the identical 23 Villa players, in the same order, as the previous session's
run against a completely different heap layout.

Four things were needed to make it reliable, each fixing an observed failure:

1. **Club-constrained walking.** A run only extends through players of the
   *same club* as the anchor. Walking on "looks like a player" alone bridges
   into neighbouring heap allocations — that produced a valid 28-entry vector
   belonging to **Newport County** while anchored on a Villa player.
2. **Gap tolerance (2 slots).** A squad vector legitimately contains players
   whose club reads elsewhere (loanees out) or whose name chain transiently
   fails. Stopping at the first mismatch truncated a 23-squad to runs of 14 and 17.
3. **Probe `begin` in both directions.** If a run is truncated at its *front*,
   the real `begin` is *behind* the run start, so forward-only probing can never
   find the header. This alone was the difference between failure and success.
4. **Corroborate with several squad members, and require anchor containment.**
   Harvest other same-club players from the anchor's runs, then require the
   located vector to contain them. Single-anchor discovery failed three times.

Do **not** go back to "longest run wins" — arena and league-wide lists are
longer (a 297-entry block was observed).

## Do we even need a static path?

Worth stating plainly, because it reframes the remaining work: **a static
pointer path is an optimisation, not a blocker.** `locate_vector()` already
produces exact squads from cold with no hardcoded addresses. What a static path
would buy is (a) skipping ~2 minutes of scanning per session and (b) possibly
enumerating *any* club without selecting one of its players first.

(a) is solved more cheaply by caching the header for the session. (b) is the
genuinely valuable part — but note the Newport County accident proves every club
has its own vector, so a per-club locator may get there without a static path at
all.

Recommendation: treat the two-pointermap compare as optional, and spend the
effort on the Phase 1 exit criterion instead.

## Club indexes: found. League table: blocked (see below)

Hunting the league table turned up two global club arrays instead. Both are
plain `Club*` arrays at 8-byte stride, walkable with
`scripts/lua/dump_club_array.lua`:

| Array | Contents |
| --- | --- |
| reputation-ordered | All 65 English clubs across loaded divisions, descending by reputation — Man City, Liverpool, Chelsea, Man Utd, Spurs, Arsenal… down to Lincoln, Rochdale, Plymouth Argyle. Relegated sides (Bournemouth, Watford) sit among Premier League clubs, confirming the sort is reputation, not division. |
| alphabetical | All English clubs alphabetically. Confirmed by decoding the gaps: Arsenal → Aston Villa is 8 bytes (adjacent), Aston Villa → Chelsea is 216 bytes = exactly the 27 clubs alphabetically between them. |

These are genuinely useful — they give club reputation ranking and a way to
enumerate every club in the loaded leagues, which scouting and transfers will
need. They are **not** league tables.

### Post-simulation attempt (3 Oct 2020, three match days played) — still unsolved

The save was advanced so the table held real values (Man Utd P3 W3 GD9 Pts9,
Leicester P3 W3 GD6 Pts9, Aston Villa P3 W1 D1 L1 GD-2 Pts4, West Brom P3 L3
GD-8 Pts0). Three hypotheses tested and **all three ruled out**:

1. **Table as an array of `Club*`** — the arrays found are global club indexes
   (reputation-ordered, alphabetical), not per-competition tables.
2. **P/W/D/L stored next to a club pointer** — scanned all 369 pointers to
   Leicester's record; the sequence `[3,3,0,0]` appears near none of them, at
   either 2- or 4-byte width, within a −64/+128 byte window.
3. **P/W/D/L stored on the club object** — dumped 8 KB from four clubs with
   different records (Leicester 3/3/0/0, Villa 3/1/1/1, Man City 3/3/0/0,
   Everton 3/1/2/0) and looked for an offset where every club reads as its own
   record. No offset matches, for P/W/D/L, for W/D/L, or even for points alone.

**Leading hypothesis now: FM derives the table from results rather than storing
it.** That would explain all three negatives at once, and it means the fixture
list is the real target — the table falls out of it.

Note also that goal difference is almost certainly derived (goals for minus
goals against) rather than stored, so don't key searches on GD. That mistake
cost the first attempt here.

### Fixture list: partial progress

`scripts/lua/probe_fixture.lua` scans for pointers to two clubs known to be
playing each other (Man City v Everton, 3 Oct) and reports where those pointers
sit close together. 20 co-located pairs found. The most structured:

```
CD45F680  +0  = 0x975B0CE8  (Man City)
          +8  = 0x03010001
          +12 = 0xFF00xxxx
          +16 = 0x975AE420  (Everton)
```

So: **16-byte records, each holding a club pointer plus two 4-byte fields.** The
same shape appears at `C29826D0` with 32-byte spacing. Not yet proven to be
fixtures rather than another club list with per-entry metadata — no scoreline or
date has been identified in the surrounding bytes.

### Iterative value scanning: done, and it worked mechanically

Ran the full loop on 4 Oct 2020 after another match day:

1. First scan, 4 bytes, exact value **3** (played) → **340,917** hits (writable
   memory only, which is what kept it tractable).
2. One match day simulated. Most clubs went to P4; West Ham, Newcastle (P3) and
   Tottenham (P2) did not play.
3. Next scan, exact value **4** → **5,081** survivors.

`scripts/lua/export_foundlist.lua` dumps the surviving set out of the CE GUI for
offline analysis without disturbing it.

Analysing the survivors for regular spacing found arithmetic runs at a **100-byte
stride**, lengths 15, 14, 13, 11. That looked like the table — until
`dump_table_rows.lua` walked them and found **no club pointer anywhere in or
around those rows**.

**Most likely these are per-player appearance counters, not table rows.** Players
who featured also went 3→4, and a run length of 13–15 matches a matchday squad
far better than a 20-team division. That's a lead worth following separately —
player season stats (apps, goals, ratings) are themselves a Phase 1 deliverable.

### Fourth hypothesis also ruled out: row findable by value pattern

`scripts/lua/scan_table_row.lua` AOB-scans for Aston Villa's record (P4 W2 D1 L1)
as int8/int16/int32 little-endian runs: 1046 / 438 / — hits respectively, and
none sits near an identifiable club pointer, club UID, or club row ID.

### Where that leaves the league table

Six approaches have now failed: array of `Club*`; P/W/D/L near a club pointer;
P/W/D/L on the club object; iterative value scan; AOB on the value pattern; and
(2026-08-15) the three per-club structures found on the render path via the
debugger. The consistent theme is that **nothing linking a club to its record is
stored the way we keep assuming**.

Two candidate explanations remain, and they suggest different next moves:

1. **The table is derived from results.** Then there is nothing to find, and the
   fixture/results list is the only real target.
2. **The row exists but references its club indirectly** (an index into a
   competition-local array, not a pointer or UID). Then it is only reachable from
   the competition object, which we have never located.

**Cheapest next step: one more sim + next-scan for 5.** That cuts the 5,081
further and, crucially, lets the two populations be told apart — per-club rows
should form a group of ~17–20 at consistent stride, whereas per-player groups
are ~14–16 per club.

**If that fails, switch technique entirely.** Blind scanning is exhausted; use
CE's debugger instead — "Find out what accesses this address" on a surviving
counter while the league table screen renders will point straight at the code
that reads it, and the register state gives the structure base. That is a much
stronger tool for this and has not been tried.

### DEBUGGER ROUTE TRIED 2026-08-15 — table still unlocated, but real progress

The debugger escalation above was taken. Full account in
`docs/session-log/2026-08-15-debugger-league-table.md`. Headlines:

**CE's debugger works on FM21.** Hardware access breakpoints *and* execute
breakpoints set, fire and remove cleanly, FM stays responsive, no crash across a
dozen arm/navigate/stop cycles. FM21's documented anti-tamper does not block it.
This was previously an open question and it unlocks a whole class of technique.

**A competition-scoped 20-club collection provably exists.** `fm.exe+1440BCF1D`
sits on the club-name render path (`RBX` = club object, `RAX` = its name pointer).
During a league-table render it is called **once per club, all 20 Premier League
clubs, in alphabetical order, at an identical `RSP` (`811ECF0`)** — a single loop
over a single collection. That is the first hard evidence of the competition
object's club list. Note the collection is **alphabetical, not table-ordered**, so
standings order is applied later.

**All 20 PL club object addresses are now known** (recorded in
`scripts/lua/find_competition.lua`), up from four.

**Three per-club structures were found on the render path and all three were
tested against the live table and ruled out:**

| Series | Where | Verdict |
| --- | --- | --- |
| `CA22xxxx` | stack[10], immediate frame | No P/W/D/L/Pts at any offset in 0x400 (width 1/2/4). Vector at `+0x10` has sizes 0–69, unrelated to matches played. Nothing in writable memory points at it. |
| `BBD9xxxx` | stack[77]/[102]/[115], caller frames | **`+0x30` is the club's own pointer for all 20** — a genuine per-club competition record. No table values in its first 0x400. |
| `C28…/A60…` | `BBD9xxxx+0x38` | No match; best near-miss 8/20 = noise. |

The matching was done against the real on-screen table (4 Oct 2020), and the
transcription was validated by two invariants — `W+D+L == P` and `Pts == 3W+D`
hold for all 20 rows — so the transcription is not the weak link in these
negatives.

**Sixth approach also ruled out: the 20 clubs are not a fixed-stride `Club*`
array.** 919 anchor hits × 17 strides produced nothing above 7/20. Don't redo it.

**Both leads were followed on 2026-08-16 — see below.**

**Technique worth reusing generally:** capture N stack qwords at a breakpoint and
look for a slot whose value moves by a *constant delta* between iterations — that
is what surfaced both per-club series. The stack grows down, so `RSP+N` walks
**up** into caller frames; 48 qwords was too shallow, 160 reached the caller.

**Two API notes:** `AOBScan` returns `nil` (not an empty list) on zero hits. And
`clubName`-style resolution of `[p+0xB8]+4` has false positives — UI descriptor
objects resolve as clubs named `number`, `time`, `hashtag`, `person`, `team`.
Filter on known club addresses when precision matters.

### RESOLVED 2026-08-16: the render loop is found; the numbers are DERIVED

Full account in `docs/session-log/2026-08-16-table-render-loop.md`.

**`fm.exe+1455A87E3` IS the league-table render loop.** `RBX` holds the club
object and the loop visits all 20 clubs **in exact league-table order**, at a
constant `RSP` (`811DD30`):

```
Leicester | Man City | Man Utd | Liverpool | Crystal Palace | Aston Villa |
Southampton | Arsenal | Everton | Sheff Utd | West Ham | Leeds | Wolves |
Burnley | Chelsea | West Brom | Fulham | Tottenham | Newcastle | Brighton
```

1st→20th, matching the screen exactly. **League position is therefore readable
today** via `scripts/lua/watch_render_caller.lua` — and position is `PLAN.md`'s
primary outcome measure (board objectives), so this is the part that mattered most.

**`fm.exe+1440DB515` is NOT the loop** — it is a generic name-formatting helper
(12,582 hits per navigation, only 2 of 600 records touching a club). Don't break
there.

**P/W/D/L/Pts are not stored as integers anywhere on the render path.** Swept
systematically, all at widths 1/2/4 against P/W/D/L/Pts/Pos:

| Tested | Result |
| --- | --- |
| `CA22` per-club objects, 1 KB | no match |
| `BBD9` per-club records, **8 KB** | no match |
| `BBD9+0x38` sub-objects, 1 KB | no match |
| 13 club-pointer arrays incl. entry payloads | no match |
| **15 distinct per-club pointer series in the ranked frame, 2 KB each** | **no match** |

That confirms this file's original hypothesis — FM derives the table from results
rather than storing it — with a systematic sweep rather than a guess.
Corroborating detail: `R8` in the ranked frame held `0x657473656369654C`, i.e. the
bytes `L e i c e s t e` inline. **The render path passes strings, not numbers**,
which is exactly why every integer scan has failed.

**Do not re-scan for integer P/W/D/L/Pts.** If those values are genuinely wanted,
the two viable routes are (a) intercept the string formatting on the render path,
or (b) OCR via `scripts/vision/` — which for the *human-knowledge* condition is
arguably more faithful anyway, since it reads exactly what a player sees.

**New tooling, both CE-free** (CE's Lua engine is single-threaded and a long
`AOBScan` blocks everything with no way to interrupt it):
- `scripts/win/read_mem.ps1` — read fm.exe memory via `ReadProcessMemory`
- `scripts/win/dump_many.ps1` — dump hundreds of regions in one pass
- `scripts/win/focus.ps1` — reliable window focus (`SetForegroundWindow` alone
  silently fails; needs `AttachThreadInput` + `SetWindowPos` + verify)

Both readers are deliberately **read-only** (`PROCESS_VM_READ` only). The write
layer is Phase 2 and must be UI-equivalent by construction — don't add a poke.

### Superseded: pre-simulation notes on why this was blocked

This is the technique that actually suits the problem and hasn't been tried,
because until the save was advanced there were no values to scan for:

1. Pick a club with a unique table value — Crystal Palace on **7 points** is the
   only 7 in the table.
2. CE value scan for 7 (4 bytes).
3. Simulate one match day so Palace's total changes (7 → 8 or 10).
4. "Changed value" / next-scan for the new total.
5. Two or three iterations should reduce millions of hits to a handful.

This is standard CE practice and is far more reliable than structural guessing.
It needs the ability to advance the save between scans, which is now established
as acceptable on a copy.

### Why the league table was blocked before the save was advanced

The save sits at 27 July 2020, before a ball is kicked. **Every table cell is
zero** — P0 W0 D0 L0 GD0 Pts0 for all 20 clubs — and the on-screen table is
sorted alphabetically because there is nothing to sort by.

That removes the technique that would normally crack this open: you find a table
by scanning for a distinctive value (a club on 7 points, a goal difference of
-3) and narrowing. With every field zero and every row identical, there is
nothing to search for, and an array of 20 row-structs full of zeros is
indistinguishable from any other zeroed memory.

**Recommendation: advance the save several match days first**, then find the
table by value-scanning a known points total. This needs a decision, since it
changes game state — do it on a *copy* of the save, not the working one. The
same applies to fixtures: results and dates become far easier to identify once
some exist.

Tooling written along the way and worth reusing:
- `scripts/lua/probe_league.lua` — scans for pointers to several known clubs of
  the same league and clusters the hits, reporting dominant stride per cluster.
- `scripts/lua/dump_club_array.lua` — walks a `Club*` array and prints it.

## Next steps
2. **Find what populates `pCurrentClub`** — see above. Until then the 30 club
   fields (finances, facilities, stadium) are untested, and club finances are
   needed for any transfer decision.
3. **Club and competition lists.** `find_club_players.lua` found nothing in the
   club object's first 4 KB; widen the scan and add a second level (club →
   member object → array) before concluding the list isn't hanging off the club.
   Fixtures and league tables are still completely unexplored.

Phase 1's exit criterion — "one script call produces a clean JSON snapshot of an
entire save's key state" — is **not met**. The player layer is done and verified;
club, competition and fixture state are not.
