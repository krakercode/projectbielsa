# Session Log — 2026-08-16 (Phase 2: reading the selected XI)

## Session metadata

- **Date:** 2026-08-16
- **Phase(s) touched:** Phase 2 (write layer — reconnaissance and the read half)
- **Starting point:** Phase 2 was at zero. League-table work concluded the previous
  session (see `docs/session-log/2026-08-16-table-render-loop.md`). FM and CE still
  on the same PIDs since 2026-08-15 16:02.
- **Access available this session:** Full desktop; FM21, Cheat Engine and Ollama running.

## What did it do?

1. **Confirmed the process was unchanged** (fm=22352, CE=11624) — but discovered
   that *same process is not sufficient* for an address to stay valid: the squad
   vector recorded in `squad.json` (`D73E6ED0`) had been freed and its memory reused
   by an unrelated tag/pointer structure. Re-located it with `locate_vector()`:
   header `CEAA0240` → begin `DCA49780`.
2. **Found the save had no tactic at all.** The Tactics screen was still showing the
   initial "choose a tactical style" wizard, and Squad said "You need to create a
   tactic before you can pick your team." FM had been auto-picking for the four
   matches played. **There was no selected XI to find.**
3. **Created a tactic** — Fluid Counter-Attack / Cautious 4-3-3 DM Wide (both the
   assistant's recommendations) — then used Quick Pick to fill the XI.
4. **Checked the vendored cheat table for anything selection-related: nothing.**
   The `Positions/GK…ST` fields at `0x204`–`0x212` are positional *ability ratings*,
   not selection.
5. **Differential test on the player records.** Dumped all 23 Villa player records
   (2 KB each) via `scripts/win/dump_many.ps1`, swapped Neil Taylor out for Matthew
   Targett at DL, dumped again, diffed.
6. **Scanned for the XI as a pointer array** (`scripts/lua/find_lineup.lua`), then as
   UIDs (`scripts/lua/scan_ptr.lua`, `scan_u32`), using a swap-and-rescan diff.
7. **Wrote `scripts/manager/read_lineup.js`** to parse the structure that was found,
   and verified its output against the Tactics screen.

## Did it achieve its goals?

Goal was Phase 2: the write layer, starting with `set_lineup()`.

**Partially — the read half is done and verified; the write half is not.**

**Achieved: the selected XI is readable, in positional order, verified.**
`read_lineup.js` produces:

```
GK  Martínez   DM   Nakamba    STC  Watkins
DR  Cash       MCL  McGinn     S1-S8  Steer, Hause, Sanson, Davis,
DCR Konsa      MCR  Barkley           Taylor, Heaton, Traoré, Douglas Luiz
DCL Mings      AMR  El Ghazi
DL  Targett    AML  Grealish
```

which matches the Tactics screen player-for-player, including the bench. That is
the "confirmed by re-reading state" half of Phase 2's exit criterion.

**Not achieved: nothing can be written yet.** The structure found is almost
certainly a UI data model, not the authoritative tactic store — see below. So
`set_lineup()` remains unimplemented and `actions.lua` is still stubs.

## Why did it do what it did?

- **Created a tactic rather than stopping to ask.** It is a hard prerequisite —
  without one there is literally no XI in memory to find — it is reversible, the
  save was backed up, and `phase1-notes` already records this save as a dev save
  rather than a clean experiment start. Picked the assistant's own recommendations
  so the choice is defensible if the save gets reused.
- **Differential analysis before scanning.** Dumping 23 player records before and
  after a single swap is cheap, needs no Cheat Engine, and definitively answers
  "is selection a field on the player?" before any effort goes into scanning.
- **Swap-and-rescan rather than a single scan.** A single scan for a player's UID
  returns hundreds of hits. Scanning while he is selected, then again after
  benching him, and intersecting *in both directions*, reduces that to the slots
  that genuinely track "who plays at DL".

## What did it learn?

- **Team selection is NOT stored on the player record.** Swapping a starter for a
  sub changed **zero bytes** across all 23 records at 2 KB each. Clean negative.
- **The selection list layout**, verified live:
  ```
  +0x00  u32  player UID
  +0x04  u32  length of first name
  +0x08  ..   first name, UTF-8
  +N     u32  length of last name
  +N+4   ..   last name
  ```
  Records are variable-length and laid out in **positional order** — GK, DR, DCR,
  DCL, DL, DM, MCL, MCR, AMR, AML, STC, then S1…S8. The UID repeats later in each
  record, which is why a UID scan returns two hits per entry.
- **The strings are length-prefixed, not zero-terminated.** Scanning for a NUL runs
  past the name into the next length prefix. This cost a debugging round.
- **FM keeps ELEVEN identical copies of this structure.** Combined with the inline
  display names, that is the shape of a UI data model rather than the canonical
  tactic object. It tracked every swap correctly so it is trustworthy for *reading*,
  but **writing into it would very likely change only what is drawn**. Recorded
  prominently in `read_lineup.js` — do not build `set_lineup()` on it.
- **Same process ≠ same addresses.** The squad vector from a dump 17 hours earlier
  had been freed and its memory reused, despite fm.exe never restarting. Always
  re-validate before trusting a recorded heap address, even within one session.
- **Unaligned scan hits are a useful signal, not noise.** The UID hits landed at
  unaligned addresses precisely because the records are packed serialized data.

## What went wrong?

- **Chased a false positive first.** The pointer-based scan surfaced exactly one
  heap slot (`CDFF2708`) that held a starter's pointer only while he was selected.
  It turned out to be a UI property table — neighbouring qwords decode as `"widt"`,
  `"name"` interleaved with pointers. Reading the surroundings is what caught it;
  taking the single clean hit at face value would have been wrong.
- **Two parser bugs in `read_lineup.js`**, both mine: I derived the last-name offset
  as `+5` instead of `+4`, and used a zero-terminated string reader on
  length-prefixed data. Both were found by dumping the raw bytes and reading them by
  hand rather than by guessing.
- **Misclicked in FM twice** — the tactical-style list re-flows as it expands, so the
  first click landed on Route One instead of Fluid Counter-Attack; and clicking a
  player's name opens a profile card rather than the swap dropdown, which needs the
  chevron specifically.
- **The write layer is still at zero.** `actions.lua` remains three stubs that throw.
  The authoritative selection store is unlocated, and that is the whole remaining
  substance of Phase 2.

## Addendum — hunting the authoritative store

Continued after the above, using `scripts/lua/watch_write.lua` (new) and
`scan_aob()` added to `scripts/lua/scan_ptr.lua`.

**A write breakpoint on a UID slot fired, but the writer is generic memcpy.** Put
`bptWrite` on `DF9B0711` (the DL slot in one copy), changed the DL player, trapped
**3 writes — all at `RIP=7FFA7D7844D7`**, which is outside fm.exe's range
(`~0x140000000`) and so is a system-DLL `memcpy`/`memmove`. The copies are bulk
assembled by serialization code, not written field by field. The fm.exe return
addresses on the stack are string/container helpers, so following them is
expensive archaeology rather than a short hop to the source.

**Four further negatives on the canonical store**, all clean:

| Hypothesis | Test | Result |
| --- | --- | --- |
| Field on the player record | 23 records × 2 KB, before/after a swap | zero bytes changed |
| Packed array of UIDs in positional order | AOB scan, two adjacent starters' UIDs | no hits |
| Packed array of player pointers in positional order | AOB scan, two adjacent starters' pointers | no hits |
| Any contiguous XI array in positional order | re-analysed all 15 `find_lineup` candidates | every one is in **squad** order, none positional |

So selection is almost certainly stored as **per-slot records with position, role
and duty interleaved** (which is what a tactic slot actually needs), or in a
non-contiguous structure reachable only from the tactic object — which remains
unlocated, exactly like the competition object did.

**What this changes.** `PLAN.md` Phase 2 says to prefer direct memory writes and
treat simulated clicks as "a last resort". The evidence now argues the other way
for `set_lineup()` specifically:

1. **UI simulation is definitionally UI-equivalent**, which `PLAN.md` elsewhere
   requires as a *structural* property — "not developer discipline ... one
   violation invalidates a run". Clicking the swap dropdown cannot violate it.
2. **It is already proven.** Four lineup swaps were driven end to end through the
   UI this session, including reading back the result from memory to confirm.
3. **A raw memory write would bypass game logic.** Changing a lineup triggers
   validation, role/duty assignment and tactical familiarity. Writing a UID into a
   slot risks a state the engine never agreed to — a correctness problem, not just
   a fairness one.
4. **The memory route is blocked anyway** until the tactic object is found.

That is a genuine architectural decision rather than a detail, so it is being put
to the user rather than settled unilaterally.

---

## Next session should probably

1. **Find the authoritative selection store, not another copy.** The eleven copies
   are UI models. The most promising route is the technique that cracked the league
   table: set an access breakpoint on one of the UID slots and see what code
   *writes* it — the writer will be reading the canonical structure. See
   `scripts/lua/watch_club_access.lua` for the pattern, and note `bptWrite` rather
   than `bptAccess` is what is wanted here.
2. **Decide memory-write vs UI-simulation for the write layer, deliberately.**
   `PLAN.md` requires the write layer to be UI-equivalent *by construction*.
   Simulating the swap dropdown is definitionally UI-equivalent and already proven
   to work this session (two swaps driven end to end); a memory write is faster but
   needs the fairness property argued rather than assumed. This is a design decision
   worth making explicitly before building.
3. **Do not re-diff the player records for selection.** Zero bytes changed across
   all 23 at 2 KB. It is not there.
