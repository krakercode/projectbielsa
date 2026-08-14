# Project Bielsa — FM21 AI Manager

Claude plays Football Manager 2021, between matches and live during matches, via Cheat Engine memory access to `fm.exe`. See [PLAN.md](PLAN.md) for the full project plan and phase breakdown.

Single-player, offline modding of the user's own game saves only — no online/multiplayer interaction.

## Status

**Phase 0 complete** — Cheat Engine attaches to `fm.exe` and the FM21-Cheat-Table reads live player data (CA/PA/attributes) with no anti-tamper blocker. See [docs/phase0-feasibility.md](docs/phase0-feasibility.md) for details. Now starting **Phase 1 — Data Layer: Full-Squad Read Access**.

## Repo layout

- `PLAN.md` — full project plan (all phases)
- `docs/` — feasibility notes, research findings, pointer maps as they're discovered
- `cheat-table/` — the FM21 Cheat Engine table (`.CT`) and notes on pointers found in it
- `scripts/lua/` — Cheat Engine Lua scripts (state dump, write actions) — run inside Cheat Engine attached to `fm.exe`
- `scripts/python/` — the orchestration controller (Phase 4+) that talks to Cheat Engine and to Claude
- `data/` — local JSON state snapshots and decision logs (gitignored — saves and dumps are local only)

## Requirements

- Football Manager 2021 (Steam), patched to the latest 21.4.x build
- Cheat Engine, latest stable (the vendored table was tested against 7.2 — fall back to that specific version only if attach/pointers fail on newer CE)
- Python 3.10+ (for the controller, from Phase 4 onward)
