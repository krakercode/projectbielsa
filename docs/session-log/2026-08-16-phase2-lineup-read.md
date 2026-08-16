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

## Addendum 2 — the write layer works

The user chose "both in parallel": ship UI-driven writes now, keep hunting the
tactic object as separate work rather than as a blocker.

**`set_lineup()` is implemented and verified.** `scripts/manager/set_lineup.js`
applied a two-position change (DL → Targett, STC → Davis) entirely by script, and
the result was confirmed **both** by re-reading the selection from memory and by
looking at FM's tactics screen. That is Phase 2's exit criterion for lineups —
"can change a lineup in a live save via script, confirmed by re-reading state".

Two things had to be settled first, both unknowns that could have sunk the approach:

1. **Does FM accept synthetic input at all?** Yes. `scripts/win/click.ps1` uses
   Win32 `SendInput`, and a scripted click opened the swap dropdown. This mattered
   because the eval has to run unattended — an agent-in-the-loop clicking tool is
   not a write layer.
2. **The swap dropdown's candidate order is NOT stable.** The same player appeared
   2nd in one opening and 4th in another, so clicking a row by index can never be
   made reliable. **Drag-and-drop is the right primitive**: both endpoints are
   fixed list rows, and which player occupies which row is known from memory.
   Verified live — dragging S5 onto the DL row swapped them correctly.

Design details worth keeping:

- **Rows are mapped by name, never by shared index.** The UI shows MCR *above* MCL;
  the serialised data has MCL first. Assuming one order for both would silently
  swap the two central midfielders.
- **The selection is re-read between drags**, because an earlier swap can move a
  later target's row.
- **Verification compares against what the game did, not what we intended** — it
  re-reads and checks each requested slot, and exits non-zero on mismatch.
- `-ExecutionPolicy Bypass` is passed per child process because the machine's
  policy blocks `.ps1` files; it changes no machine or user setting.

`scripts/lua/actions.lua` has been rewritten from a bare stub into an explanation
of why the memory-write path is deliberately not implemented, so the next session
doesn't "fix" it by poking memory and quietly break the UI-equivalence contract.

## Addendum 3 — locating the list from cold, and a nasty discovery

`set_lineup.js` took a `--base` address that dies with the process, so the whole
write layer was one restart from useless. Fixing that produced two new tools and
one finding that would otherwise have silently corrupted results.

**`scripts/win/scan_mem.ps1` — a CE-free memory scanner.** Enumerates committed
writable regions via `VirtualQueryEx` and searches them, with the inner byte loop
in C# because PowerShell over ~1 GB is hopeless. **2.5 GB scanned in 2.4 s**,
against 20–45 s for CE's `AOBScan` — and it doesn't block anything, unlike CE's
single-threaded Lua engine.

**`scripts/manager/locate_lineup.js` — finds the selection list from cold.** It
anchors on player UIDs and names, which are *game* data and identical across
restarts, unlike every address in the process. A persisted roster
(`data/roster/aston-villa.json`) supplies them. For each roster player it builds
the exact record signature (`u32 UID | u32 name length | name`) and scans for it,
then finds valid record chains around each hit.

**Confirmed the list really does move**: the base found earlier that day
(`DF9B0611`) no longer parsed at all by the time this ran, without any restart.

**The nasty discovery: copies go stale, and majority does not save you.** FM keeps
many copies of the list and old generations survive. Measured live:

```
 23 copies  ... DL=Taylor    STC=Watkins     <- STALE (pre-change)
 21 copies  ... DL=Targett   STC=Davis       <- LIVE  (matches the UI)
  7 copies  ... DL=Targett   STC=Watkins     <- partially stale
```

The stale generation **outnumbered** the live one, so a count-based rule picks the
wrong answer with full confidence. A separate family had Björn Engels — an injured
centre-back, GK rating 1 — in the GK slot, and *that* family was the most numerous
of all before filtering.

Two rules were added, and only one of them actually works:

- **Plausibility (works):** the GK slot must hold a goalkeeper. Roster now carries
  position ratings, so this is checkable. Kills the Engels family outright.
- **Majority (does not work):** as measured above.

So **liveness cannot be established by reading alone**. It is inherently
behavioural — the live copy is the one that changes when the lineup changes. The
locator therefore now prints a loud warning listing every variant and states that
its pick is not guaranteed current, rather than silently returning a stale XI.

Two bugs found on the way, both mine: `chainAt` required records to be laid end to
end when they are actually ~0x25 bytes apart (so it found exactly one record and
stopped), and `dump_many.ps1` returned *empty* buffers for any window touching an
unmapped page, which made the locator look like it had found nothing. Both readers
are now page-tolerant and zero-fill what they cannot read.

## Addendum 4 — liveness resolved, and a near-miss worth recording

**`set_lineup.js` now needs no address at all.** It locates candidate copies, and
resolves which is live *behaviourally*: snapshot every candidate, make the first
drag, and whichever copy changed is the live one. It then re-plans against that
copy to a fixpoint, which also repairs the first drag if it was planned off a
stale copy. Verified end to end with no `--base`.

Two bugs surfaced in testing, and the second one matters a lot:

1. **Silent no-op.** Planning off `bases[0]` — which happened to be stale — made
   it conclude "already matches the requested XI" and do nothing. Fixed: a no-op
   is only accepted if **every** copy agrees.

2. **A recycled buffer reported a completely wrong XI.** A verification read came
   back as *Wes Morgan, Nampalys Mendy…* — **Leicester's** squad. The buffer had
   been freed and reused between the drag and the read, seconds apart, and it
   parsed perfectly. The drags themselves had worked correctly; only the read was
   wrong, and the tool did fail loudly rather than claim success.

   Fixed by validating every parse against the roster: if any entry is not one of
   our players, the buffer is no longer our selection list. This is the important
   lesson of the day — these are **transient render buffers**, not stable
   allocations, so nothing may be cached and everything must be re-validated.
   Recorded prominently in `docs/LIVE-STATE.md`.

Final verified run, fully automatic:

```
locating the selection list...
  3 candidate copies: 0xA991DFBF, 0xC46B64DF, 0xC47B22EF
  dragging S5 -> DL
  live copy identified: 0xC47B22EF (1 of 2 copies updated)
  dragging S4 -> STC  (live)
  OK   DL  expected uid 28084863, got 28084863 (Targett)
  OK   STC expected uid 28107730, got 28107730 (Davis)
set_lineup: verified
```

Confirmed against FM's tactics screen afterwards.

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
