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

## Full-squad read: working, with a caveat

`scripts/lua/dump_squad.lua` dumps a whole squad, not just the selection.
Verified live: 20 Aston Villa players with correct CA/PA/attributes and correct
first+last names for all of them.

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

### Known limitation

It returned 20 where the squad is 23. It picked an arena copy whose neighbouring
slots had been overwritten since, truncating the run. **Fix:** prefer a run
backed by a real vector header — scan for a qword equal to the run's start and
require the next qword to equal its end — falling back to the longest run only
when no header is found. Not implemented blind on purpose; it needs a live
session to verify, which is exactly the mistake that produced the offset bug.

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

## Next steps

1. **Vector-header validation in `dump_squad.lua`** (above) — should take it
   from 20/23 to the exact squad.
2. **A stable pointer path.** The right tool is CE's Pointer Scanner against
   `0x6B7CC8C0`: it handles exactly this case (target embedded by value, reached
   via offsets from a static module address). Heavyweight — minutes of scanning
   and large result files — so give it its own session. A static path would
   remove the per-call memory scan and let us enumerate *any* club, not just
   the one whose player is selected.
3. **Club and competition lists.** `find_club_players.lua` found nothing in the
   club object's first 4 KB; widen the scan and add a second level (club →
   member object → array) before concluding the list isn't hanging off the club.
4. **Staff.** `pCurrentStaff` read 0 all session because no staff member was
   ever selected — the staff path is untested, not known-broken.
