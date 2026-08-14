# Cheat Table

This folder holds the Cheat Engine table (`.CT`) used to attach to `fm.exe` and the notes on what pointers it exposes.

- Base table: [xAranaktu/FM21-Cheat-Table](https://github.com/xAranaktu/FM21-Cheat-Table), vendored as-is into `FM21-Cheat-Table/` (upstream `.git` stripped — it's tracked as plain files in this repo, not a submodule). The actual table is `FM21-Cheat-Table/Source/fm.CT`.
- Per its README, this table was **tested with Cheat Engine 7.2 on Win10 x64, Steam game version v21.3**. Our install is likely a later build (v21.4.0-ish) — see `docs/phase0-feasibility.md` for the version-confirmation step.
- As Phase 1 extends it with full-squad/club/competition pointers (found via AOB scans, following the FM23/24 community tables' technique), keep those additions in `fm.CT` itself and log what was added and how it was found below.
- `parse_ct.js` — parses `fm.CT`'s XML into `fields.json` (every leaf data field: description path, symbol, pointer-offset chain, type). `generate_dump_lua.js` — turns `fields.json` into `../scripts/lua/dump_state.lua`. Regenerate both if `fm.CT` changes. See `../docs/phase1-notes.md`.

## Pointer log

- Base table provides: pointer for current player, pointer for current club, pointer for current staff (single-selection only, not full-list walks) — confirmed working live in Phase 0 (CA/PA/attributes read correctly for a real player).
- `fields.json` now has the full extracted offset chain for every field the table exposes: 106 player fields, 30 club fields, 83 staff fields. Not yet verified field-by-field against live data beyond the ones visible during the Phase 0 attach test (CA, PA, and a few others).
- Squad-list / full-club-list / competition-table pointers: **not found yet**. Needs live AOB/value scanning — see `../docs/phase1-notes.md` for the plan.
