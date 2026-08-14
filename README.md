# Project Bielsa — FM21 AI Manager

Claude plays Football Manager 2021, between matches and live during matches, via Cheat Engine memory access to `fm.exe`. See [PLAN.md](PLAN.md) for the full project plan and phase breakdown.

Single-player, offline modding of the user's own game saves only — no online/multiplayer interaction.

## Status

**Phase 0 complete** — Cheat Engine attaches to `fm.exe` and the FM21-Cheat-Table reads live player data (CA/PA/attributes) with no anti-tamper blocker. See [docs/phase0-feasibility.md](docs/phase0-feasibility.md) for details.

**Phase 1 in progress** — `scripts/lua/dump_state.lua` now reads every field the base table exposes for the currently-selected player/club/staff and serializes it to JSON (generated from `fm.CT` itself, see `cheat-table/parse_ct.js` + `cheat-table/generate_dump_lua.js`), but it's **untested against a live game** — no live session was available to verify it. The full-squad array walk (the actual Phase 1 exit criterion) hasn't been started — it needs live AOB scanning in Cheat Engine. See [docs/phase1-notes.md](docs/phase1-notes.md) for what to check first and the scan plan.

**Phase 4 design work started early** — [docs/control-interface.md](docs/control-interface.md) works out how models actually drive the manager: an agentic tool-use loop (read tools + write tools per decision event) rather than one giant JSON-in/JSON-out call, where cheat/human mode plugs in, how manager "personality" (risk tolerance, transfer aggressiveness, etc.) gets configured separately from game state, and the model-agnostic adapter shape. Design only — no code yet, and it depends on Phase 1/2 read/write access existing first.

Two separate logging conventions exist — don't confuse them:

- **Dev session log** (`docs/session-log/`) — for Claude sessions working *on this codebase*. This project spans many dev sessions with no memory between them; the log carries context forward (what happened, why, what's still unverified). See `CLAUDE.md`.
- **Manager session report** (`docs/manager-log/TEMPLATE.md`) — for the *in-game AI manager itself* (Phase 4+, once it exists) to fill out after a play session — a match, a run of fixtures, a transfer window. A human-readable reflection distinct from the machine-oriented decision log described in `docs/control-interface.md`. Not active yet — the orchestration loop that would produce these doesn't exist until Phase 4.

## Repo layout

- `PLAN.md` — full project plan (all phases)
- `CLAUDE.md` — instructions for Claude sessions working in this repo (dev session-log convention)
- `docs/` — feasibility notes, research findings, pointer maps as they're discovered
- `docs/session-log/` — per-*dev*-session log of what was done, why, and what's still open (see `TEMPLATE.md`)
- `docs/manager-log/TEMPLATE.md` — template for the in-game AI manager's own post-play-session reflection (Phase 4+)
- `cheat-table/` — the FM21 Cheat Engine table (`.CT`) and notes on pointers found in it
- `scripts/lua/` — Cheat Engine Lua scripts (state dump, write actions) — run inside Cheat Engine attached to `fm.exe`
- `scripts/python/` — the orchestration controller (Phase 4+) that talks to Cheat Engine and to Claude
- `data/` — local JSON state snapshots, decision logs, and manager session reports (gitignored — saves and dumps are local only)

## Requirements

- Football Manager 2021 (Steam), patched to the latest 21.4.x build
- Cheat Engine, latest stable (the vendored table was tested against 7.2 — fall back to that specific version only if attach/pointers fail on newer CE)
- Python 3.10+ (for the controller, from Phase 4 onward)
