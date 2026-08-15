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

### Why the league table is blocked right now

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
