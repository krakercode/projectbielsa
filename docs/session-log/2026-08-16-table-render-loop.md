# Session Log — 2026-08-16 (the table render loop, and why the numbers aren't there)

## Session metadata

- **Date:** 2026-08-16 (continuation of the debugger session; FM and CE never restarted, so the whole day shares one heap layout)
- **Phase(s) touched:** Phase 1 (league table / competition object)
- **Starting point:** `docs/session-log/2026-08-15-debugger-league-table.md` — the debugger worked, a 20-club competition collection was proven to exist, but the table was unlocated and three per-club structures had been ruled out.
- **Access available this session:** Full desktop, FM21 + Cheat Engine + Ollama all still running on the same PIDs as the previous session.

## What did it do?

1. **Retargeted `find_row_array.lua`** from the `CA22` objects (zero referrers) to the
   `BBD9` per-club records. Found the container class: **335+ arrays holding pointers
   to all 20 `BBD9` records**, 13 of them 20/20 at strides 8/16/32.
2. **Ruled all of them out.** No array is in league-table order; no entry payload
   encodes P/W/D/L/Pts/Pos at any offset or width. The stride-16 payload is a small
   enum (1–3 plus `0xFF00` constants), not a sort key.
3. **Wrote `scripts/win/read_mem.ps1`** — reads fm.exe memory directly via
   `ReadProcessMemory`, no Cheat Engine involved.
4. **Re-dumped all 20 `BBD9` records at 8 KB** (up from 1 KB) — the "cheapest
   remaining shot" from the last log. Still nothing.
5. **Wrote `scripts/win/focus.ps1`** after losing time repeatedly to failed window focus.
6. **Wrote `scripts/lua/watch_render_caller.lua`** and broke on `1440DB515` — the
   caller. **It is a generic name-formatting helper**, not the loop: 12,582 hits in one
   navigation, and only 2 of 600 captured records touched a known club.
7. **Added a capture-time club filter** and broke on the next frame up, `1455A87E3`.
   **That is the table render loop.**
8. **Wrote `scripts/win/dump_many.ps1`** and swept all 15 distinct per-club pointer
   series visible in that frame — 300 regions × 2 KB in one pass — against the real table.

## Did it achieve its goals?

Goal was: use the caller breakpoint to find the league table.

**Partially, and the partial result is the interesting one.**

**Achieved — the render loop is found and league position is readable.** At
`fm.exe+1455A87E3`, `RBX` holds the club object and the loop visits all 20 clubs **in
exact league-table order**:

```
Leicester | Man City | Man Utd | Liverpool | Crystal Palace | Aston Villa |
Southampton | Arsenal | Everton | Sheff Utd | West Ham | Leeds | Wolves |
Burnley | Chelsea | West Brom | Fulham | Tottenham | Newcastle | Brighton
```

That is 1st→20th, matching the on-screen table exactly, and it appeared twice in the
capture. `RSP` is constant (`811DD30`) across all 20, so it is one loop.

**Not achieved — P/W/D/L/Pts are still not located, and there is now strong evidence
they are not stored at all.** See below. This is a much better-supported answer than
"we couldn't find them."

## Why did it do what it did?

- **Retargeted the array scan at `BBD9` rather than `CA22`** because `CA22` had zero
  referrers in writable memory, whereas `BBD9+0x30` holds the club pointer — so `BBD9`
  is the record-like structure and the thing a collection would hold pointers to.
- **Built a CE-free memory reader instead of restarting Cheat Engine.** A long
  `AOBScan` blocked CE's single-threaded Lua engine for ~25 minutes with no way to
  interrupt it. Restarting CE would have freed it but destroyed the 5,081-address
  found-list that the previous log had explicitly flagged as worth keeping — and
  worse, CE was attached as a debugger, so killing it risked taking fm.exe with it and
  losing the entire day's heap layout. Reading memory needs nothing from CE, so that
  was the safe path. The scan finished on its own in the end.
- **Deliberately kept the reader read-only** (`PROCESS_VM_READ`, never
  `PROCESS_VM_WRITE`). The write layer is Phase 2 and `PLAN.md` requires it to be
  UI-equivalent by construction; a general-purpose poke function sitting in the repo is
  exactly how that constraint gets violated by accident later.
- **Validated ground truth before matching against it.** The on-screen table was
  checked against `W+D+L == P` and `Pts == 3W+D` for all 20 rows before being used, so
  a transcription error cannot be what is producing these negatives.

## What did it learn?

- **`fm.exe+1455A87E3` is the league-table render loop.** `RBX` = club object, visited
  in ranked order, constant `RSP`. **League position is therefore readable today**, and
  position is `PLAN.md`'s primary outcome measure (board objectives) — arguably more
  valuable for the eval than P/W/D/L.
- **`fm.exe+1440DB515` is a generic name-formatting helper, not the loop.** Worth
  recording so nobody breaks on it again: 12,582 hits per navigation.
- **The table numbers are almost certainly derived and never stored as integers.**
  Everything on the render path has now been swept:
  | Tested | Result |
  | --- | --- |
  | `CA22` per-club objects, 1 KB | no match |
  | `BBD9` per-club records, 8 KB | no match |
  | `BBD9+0x38` sub-objects, 1 KB | no match |
  | 13 club-pointer arrays + payloads | no match |
  | **15 distinct per-club series in the ranked frame, 2 KB each** | **no match** |
  All at widths 1/2/4 against P/W/D/L/Pts/Pos. This is the original hypothesis in
  `phase1-notes.md` — "FM derives the table from results rather than storing it" —
  now backed by a systematic sweep rather than a guess.
- **The render path passes strings, not numbers.** `R8` in the ranked frame held
  `0x657473656369654C`, which is the bytes `L e i c e s t e` inline. If the club name
  arrives as an inline string, the numeric columns are very likely formatted to strings
  too — which is exactly why integer scans keep failing.
- **`SetForegroundWindow` alone silently fails**; the working recipe is
  `AttachThreadInput` + `ShowWindow` + `SetWindowPos(TOPMOST→NOTOPMOST)` +
  `BringWindowToTop` + `SetForegroundWindow`, then verify the foreground PID. Now
  `scripts/win/focus.ps1`.
- **CE's Lua Engine is single-threaded and uninterruptible.** A long `AOBScan` blocks
  every other script. Never put an `AOBScan` inside a per-result loop.
- **PowerShell shell state does not persist between tool calls** — `Add-Type` must be
  repeated every call, which is why the helpers are files now. Also: don't name a
  helper class `GC`, it collides with `System.GC`.

## What went wrong?

- **I put an `AOBScan` inside the per-result loop of `find_row_array.lua`**, so every
  reported array triggered another full-memory scan. With 335+ arrays matching, that
  ran for ~25 minutes and blocked CE completely. Entirely self-inflicted, and it forced
  the detour that produced `read_mem.ps1` — a good outcome from a bad mistake, but the
  mistake was avoidable.
- **The first caller breakpoint captured the wrong 600 hits.** Without a filter,
  `1440DB515`'s 12,582 hits filled the record cap with unrelated UI work long before the
  table rendered. Fixed by filtering at capture time.
- **My "monotonic" test for the iterator was the wrong test.** A *ranked* collection's
  entries are in rank order, not address order, so requiring monotonicity would have
  hidden it. Corrected to "any slot with 20 distinct values", which is what surfaced the
  15 series.
- **The iterator itself was never found.** Even at 160 stack qwords, no register or slot
  in the ranked frame advances with a constant stride. The collection base is further up
  still, or the loop is index-based with the index in a restored register.
- **A `type` action pasted stale clipboard content into CE's Lua Engine once**, producing
  a harmless syntax error. Worth knowing the clipboard-based typing can do that.
- **Left running:** CE's debugger is still attached to fm.exe; all breakpoints removed,
  both processes responsive. The 5,081 found-list survived.

---

## Next session should probably

1. **Decide whether the table numbers are worth more memory work at all.** Position is
   already readable and is the primary metric. If P/W/D/L/Pts are genuinely wanted, the
   two viable routes are (a) intercept the string formatting on the render path — the
   `R8` inline-string finding says that is where the numbers become visible — or (b) OCR
   via `scripts/vision/`, which is arguably *more* human-faithful for the human-knowledge
   condition since it reads exactly what a player sees.
2. **Do not re-scan for integer P/W/D/L/Pts.** Five structures and 15 per-club series
   across the whole render path have been swept at widths 1/2/4. It is not stored.
3. **Phase 2 is next by prior agreement** — the write layer, which is still at zero and
   remains the critical path. `scripts/win/read_mem.ps1` and `dump_many.ps1` make
   before/after memory diffing cheap, which is the natural way to locate the selected-XI
   structure without touching CE.
