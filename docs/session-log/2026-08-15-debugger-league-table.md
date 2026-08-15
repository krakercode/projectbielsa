# Session Log — 2026-08-15 (CE debugger vs the league table)

## Session metadata

- **Date:** 2026-08-15 (third session this day)
- **Phase(s) touched:** Phase 1 (league table / competition object)
- **Starting point:** Five approaches to the league table had failed; `docs/phase1-notes.md`
  recommended abandoning blind scanning and switching to CE's debugger, which had
  never been tried. See `docs/session-log/2026-08-15-pointer-validation.md` and
  `docs/session-log/2026-08-15-qwen-manager-setup.md`.
- **Access available this session:** Full desktop. FM21 and Cheat Engine were
  already running and still held the previous session's state, including the
  5,081-address found-list in the CE GUI.

## What did it do?

1. **Backed up all three save files** to `D:\projectbielsa-save-backup\2026-08-15-2323\`
   before touching anything, then saved in-game (FM wrote `Claude Anthropic -
   Aston Villa.fm` at 23:29 and kept its own `last save overwrite backup.fm`).
   Attaching a debugger to a live game is the risky step in this session.
2. **`scripts/lua/probe_club_anchor.lua`** (new) — verified the club addresses
   recorded in `dump_club_record.lua` are still live. **4/4 correct**, so the heap
   layout was unchanged from the league-table session and every address in the
   notes was still usable.
3. **`scripts/lua/watch_club_access.lua`** (new) — hardware access breakpoint on
   `Everton+0xB8` (the club's name-pointer field) while navigating to the league
   table. Everton was chosen deliberately: FM was parked on an Aston Villa screen,
   so the table was essentially the only thing that would read Everton's name.
4. **`scripts/lua/probe_table_ctx.lua`** (new) — interpreted the captured
   registers, and disassembled around the trapped RIP.
5. **`scripts/lua/watch_table_render.lua`** (new) — execute breakpoint on the
   instruction itself rather than one club's memory, so every club renders through
   it. Captured registers plus 48 (later 160) stack qwords per call.
6. **`scripts/lua/find_competition.lua`** (new) — scanned for the 20 PL clubs as a
   contiguous array. Written once wrongly, then rewritten (see below).
7. **`scripts/lua/find_row_array.lua`** (new) — scanned for an array of pointers to
   the per-club structures found on the render path.
8. **`scripts/lua/dump_league_rows.lua`** (new) — dumped 0x400 bytes from each of
   three candidate per-club structures for offline matching against the real table.

Snapshots written: `club_access.json`, `table_ctx.{json,log}`,
`table_render.{json,log}`, `competition.{json,log}`, `row_array.log`,
`league_rows.json`.

## Did it achieve its goals?

Goal was: crack the league table using CE's debugger instead of blind scanning.

**No — the league table is still not located.** Three candidate structures were
found on the render path and all three were tested against the real table and
ruled out. That is a genuine negative, not an untested guess (method below).

But the session was not empty, and two results are worth more than the failed
primary goal:

- **CE's debugger works on FM21.** Both hardware access breakpoints and execute
  breakpoints set, fired, and were removed cleanly, with FM responsive throughout
  and no crash across roughly a dozen arm/navigate/stop cycles. This was an open
  question — FM21 is documented as having anti-tamper — and it unlocks a class of
  technique the project had never used.
- **A competition-scoped collection of exactly the 20 Premier League clubs
  provably exists.** During a league-table render, `fm.exe+1440BCF1D` is called
  once per club, alphabetically, all 20, at an identical `RSP` (`811ECF0`) — one
  loop over one collection. `docs/phase1-notes.md` calls the competition object
  "the biggest gap"; this is the first hard evidence of its club list.

Also captured, and immediately reusable: **the object addresses of all 20 Premier
League clubs** (in `find_competition.lua`), where previously only four were known.

## Why did it do what it did?

- **Anchored on Everton, not Aston Villa.** `club+0xB8` is read by anything that
  draws that club's name, so anchoring on our own club would have buried the table
  render in noise. Parking on a Villa screen and anchoring on a club that appears
  nowhere else made the table essentially the only reader. It worked: 23 hits from
  **one** instruction.
- **Switched from an access breakpoint to an execute breakpoint.** The first
  capture anchored on one club's memory, so only Everton's calls were ever seen.
  Two registers (`R13`, `R10`) looked "constant across hits" and briefly looked
  like the container — but with a single club there was nothing for them to vary
  against. Breaking on the instruction instead let every club through, and `R13`
  and `R10` stayed constant even for FA Cup clubs, which ruled them out properly.
- **Matched candidates against the live on-screen table rather than guessing
  offsets.** The table was read off screen (Leicester P4 W4 D0 L0 Pts12, Villa P4
  W2 D1 L1 Pts7, and so on for all 20). Before using it, it was checked against two
  invariants — `W+D+L == P` and `Pts == 3W+D` — and both hold for all 20 rows, so
  the transcription is not the weak link in the negative results.
- **Did not re-run the "one more sim + next-scan for 5"** that `phase1-notes.md`
  lists as the cheapest next step. The user chose the debugger route, and the
  5,081-address found-list is still live in the CE GUI, so that option is
  preserved for a future session rather than consumed.

## What did it learn?

- **`fm.exe+1440BCF1D` is on the club-name render path.** At that point `RBX` holds
  the club object and `RAX` its name pointer. The instruction is `mov rdi,rcx`;
  the actual read is the instruction before it (hardware breakpoints trap *after*
  execution). It is generic, not table-specific — it also fires for FA Cup clubs.
- **The league table render iterates the 20 PL clubs alphabetically**, not in
  table order. So the on-screen ordering is applied later; the underlying
  collection is alphabetical (or registration-ordered).
- **All 20 PL club object addresses**, recorded in `find_competition.lua`.
- **Three per-club structures exist on the render path, and none is the table:**
  | Series | Where | Verdict |
  | --- | --- | --- |
  | `CA22xxxx` | stack[10], immediate frame | No P/W/D/L/Pts at any offset in 0x400 at width 1/2/4. Its `{begin,end,cap}` vector at `+0x10` has sizes 0–69 unrelated to matches played (Villa and Burnley are empty). Nothing in writable memory points at it. |
  | `BBD9xxxx` | stack[77]/[102]/[115], caller frames | **`+0x30` is the club's own pointer, for all 20** — a real per-club competition record. But no table values in its first 0x400. |
  | `C28…/A60…` | `BBD9xxxx + 0x38` | Also no match; best near-miss 8/20, i.e. noise. |
- **`BBD9xxxx+0x30 = club pointer` is the most useful single offset found.** It is
  the first structure this project has seen that is per-club, competition-scoped,
  and self-identifying.
- **Technique worth reusing:** capture N stack qwords at a breakpoint and look for
  a slot whose value changes with a *constant delta* between iterations. That is
  what surfaced the `CA22` and `BBD9` series. Note the direction: the stack grows
  down, so `RSP+N` walks **up** into caller frames.
- **`AOBScan` returns `nil`, not an empty list, when there are zero hits.** Worth
  knowing — it initially read as a scan failure.
- **Focus is unreliable during this workflow.** `SetForegroundWindow` alone
  silently failed several times mid-session; `AttachThreadInput` + `BringWindowToTop`
  + `SetForegroundWindow`, then verifying the foreground PID, is what worked.
  (This is on top of the known gotcha that `open_application` spawns a *new* CE.)

## What went wrong?

- **The primary goal was not met.** The league table is still unlocated. Six
  approaches have now failed rather than five.
- **`find_competition.lua` was written wrong the first time and had to be
  rewritten.** It scanned for two alphabetically adjacent club pointers as a
  16-byte pattern — which can only ever match a stride-8 pointer array, and so
  structurally could not find the row-struct layout that was the whole point of
  looking. The rewrite (scan one club pointer, then test 17 strides around each of
  919 hits) is the correct shape. Cost maybe 20 minutes and one wasted scan.
- **The first breakpoint capture was mis-designed** — anchoring on one club's
  memory meant no club-to-club variation, so "constant registers" carried no
  information. Corrected within the session, but it produced a briefly convincing
  false lead (`R13`/`R10`).
- **The first `find_competition` reporting pass flooded the log with noise** — a
  threshold of 6/20 plus a 12-result cap meant a dozen coincidental matches were
  printed and the run may have stopped before anything real. It was superseded
  rather than re-run, so *strictly* the club-array question was answered by the
  best-of pass only up to that cap. Low confidence this hides anything: the best
  score anywhere was 7/20.
- **`clubNameFast()` has false positives.** Resolving `[RBX+0xB8]+4` as a string
  matched UI descriptor objects too, yielding "clubs" named `number`, `time`,
  `hashtag`, `person`, `team`, `date`, `string`. Fixed by filtering on the 20 known
  club addresses exactly, but any future reuse of that helper should expect it.
- **Left running:** CE's debugger is still attached to fm.exe. All breakpoints were
  explicitly removed and both processes are responsive, but the debugger itself was
  not detached. If FM behaves oddly next session, detach or restart CE first.
- **Not attempted:** the deeper-frame breakpoint on the actual caller
  (`1440DB515` / `1440BE24A`), which is the obvious continuation and is where the
  loop counter must live.

---

## Next session should probably

1. **Break on the caller, not the callee.** The loop is at a constant
   `RSP=811ECF0`; the return chain captured is `1440DB515` → `1440BE24A` →
   `1455A87E3`. Setting an execute breakpoint on `1440DB515` or `1440BE24A` puts
   you *inside* the loop, where the iterator and the collection base are live in
   registers. Everything needed is in `scripts/lua/watch_table_render.lua` — only
   the address and the capture width need changing.
2. **Follow `BBD9xxxx` outward, not inward.** `+0x30` is the club pointer, so these
   are per-club competition records; the stats are simply not in the first 0x400.
   Dump a much larger range (0x2000, as `dump_club_record.lua` does) and re-run the
   same ground-truth match in `dump_league_rows.lua`. This is the cheapest
   remaining shot and needs no new technique.
3. **Do not redo the club-pointer array scan.** 919 anchor hits × 17 strides
   produced nothing above 7/20. The 20 clubs are not stored as a fixed-stride
   array of `Club*` anywhere in writable memory.
4. Still preserved and untouched: the 5,081-address found-list is live in the CE
   GUI, so `phase1-notes.md`'s "one more sim + next-scan for 5" remains available
   — but note it dies the moment CE is restarted.
