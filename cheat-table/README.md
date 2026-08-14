# Cheat Table

This folder holds the Cheat Engine table (`.CT`) used to attach to `fm.exe` and the notes on what pointers it exposes.

- Base table: [xAranaktu/FM21-Cheat-Table](https://github.com/xAranaktu/FM21-Cheat-Table), vendored as-is into `FM21-Cheat-Table/` (upstream `.git` stripped — it's tracked as plain files in this repo, not a submodule). The actual table is `FM21-Cheat-Table/Source/fm.CT`.
- Per its README, this table was **tested with Cheat Engine 7.2 on Win10 x64, Steam game version v21.3**. Our install is likely a later build (v21.4.0-ish) — see `docs/phase0-feasibility.md` for the version-confirmation step.
- As Phase 1 extends it with full-squad/club/competition pointers (found via AOB scans, following the FM23/24 community tables' technique), keep those additions in `fm.CT` itself and log what was added and how it was found below.

## Pointer log

- Base table provides: pointer for current player, pointer for current club, pointer for current staff (single-selection only, not full-list walks). Nothing beyond the base table found yet — Phase 0 attach test still pending.
