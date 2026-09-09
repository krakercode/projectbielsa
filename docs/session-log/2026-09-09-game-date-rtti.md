# Session log — game-date / RTTI investigation

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 1 / Phase 3 prerequisite — detecting that the game has advanced
- **Starting point:** the between-match decision loop worked, but Project Bielsa still had no reliable signal that in-game time had moved.
- **Access available this session:** live FM21 process, local terminal, read-only process-memory tooling.

## What did it do?

The session pursued a memory-first route for the current in-game date/time rather than OCR.

1. Searched live writable memory for values matching the visible `Sun 21:15` clock and 4 Oct 2020.
2. Found repeated structures containing apparent `21` / `15` fields and a recurring 32-bit date-like value `0x07E45916`.
3. Tested the promising structure rather than assuming the matching integers were authoritative.
4. Identified a repeated 0x110-byte object layout whose vtable is `fm.exe+0x690BE28`.
5. Added `scripts/win/rtti.ps1`, a read-only MSVC x64 RTTI resolver for FM vtable pointers.
6. RTTI proved that apparent clock structure is actually `GAME_TEAM_COMP_STATS`; its linked object is a `TEAM`. The 21/15 match was coincidence, so this route was rejected.
7. Used FM's own RTTI metadata to discover relevant date/match classes and derive their vtables, including `CURRENT_GAME_DATE_WIDGET`, `SI_DATE_TYPED_TRAITS@fmdate`, `DATE_STRING_CLIENT@fmdate`, `GAME_MATCH`, `MATCH@simatch`, `GAME_MATCH_SESSION`, `MATCH_SESSION`, and `MATCH_SCORE_TIME_PANEL@fmmatchviewer`.
8. Located live instances of the current-date widget and date-traits infrastructure. The widget itself does not contain the authoritative date inline, so its relationships still need to be followed.
9. Scanned for `0x07E45916` and found 1,934 live copies. Dumped their surrounding memory and classified nearby FM vtables: 49 distinct nearby module/vtable candidates remain, which is small enough to classify with RTTI instead of blind rescanning.

## Did it achieve its goals?

**Partially.** The session did not yet identify and validate the authoritative current-date owner, so the game-advance signal is not finished.

It did produce two concrete advances:

- A reusable RTTI tool that turns opaque vtable addresses into actual FM C++ class names.
- A tractable candidate set for the current date: 1,934 raw copies reduced to 49 nearby class/vtable families.

Evidence that `rtti.ps1` works: resolving `0x14690BE28` returns `.?AVGAME_TEAM_COMP_STATS@@`, and resolving `0x146904430` returns `.?AVTEAM@db@@`.

## Why did it do what it did?

The visible clock/date produces too many coincidental integer matches to trust value scans alone. RTTI gives semantic evidence about the object around each candidate and is therefore a better discriminator than repeatedly tightening numeric scans.

The date widget is useful as a route into the object graph, but it is UI infrastructure. It should not be treated as authoritative merely because its name sounds correct. The target remains a stable game-state date/time owner that changes when the save advances.

## What did it learn?

- FM21 ships enough MSVC RTTI in `fm.exe` to identify many live C++ object classes from their vtables.
- `scripts/win/rtti.ps1` can recover those names using only read/query process rights.
- The 0x110-byte `fm.exe+0x690BE28` objects are `GAME_TEAM_COMP_STATS`, not clocks.
- A linked vtable `0x146904430` resolves to `TEAM@db`.
- `0x07E45916` is a strong date-encoding candidate for 4 Oct 2020: the high 16 bits are 2020 and the low portion is consistent with the date's position in the leap year. This encoding is **not yet proven authoritative**.
- `CURRENT_GAME_DATE_WIDGET` has live instances, but the date is not stored inline in the widget object.
- Static RTTI exposes `MATCH_SCORE_TIME_PANEL@fmmatchviewer`, which is a strong target once a live match exists.

## What went wrong?

The first attractive numeric hit was a false positive. Its hour/minute-looking fields matched `21:15`, but RTTI proved the object was team competition statistics. This is now documented specifically so nobody repeats the mistake.

The current-date value has 1,934 copies, so a simple exact-value scan cannot identify the authoritative owner. Heap addresses observed in this session are perishable and must not be treated as durable offsets.

One command-line example for passing multiple vtables to `rtti.ps1` was misleading under `powershell -File`; the script itself works, and the example was corrected to PowerShell array syntax.

## Next session should probably

1. RTTI-classify the 49 nearby vtable families around the `0x07E45916` copies and prioritise date/game/session owners over UI/statistics objects.
2. Follow the live `CURRENT_GAME_DATE_WIDGET` relationships to find the date source it reads rather than the rendered widget state.
3. Once a reliable current-date value is found, advance FM and verify it changes exactly as expected before integrating it as the loop's progress signal.
4. When a live match is available, inspect `MATCH_SCORE_TIME_PANEL@fmmatchviewer` and the `GAME_MATCH` / `MATCH_SESSION` family using the same RTTI technique.
