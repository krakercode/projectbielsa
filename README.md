# Project Bielsa — FM21 AI Manager

Claude plays Football Manager 2021, between matches and live during matches, via Cheat Engine memory access to `fm.exe`. See [PLAN.md](PLAN.md) for the full project plan and phase breakdown.

Single-player, offline modding of the user's own game saves only — no online/multiplayer interaction.

## Status

**Phase 0 complete** — Cheat Engine attaches to `fm.exe` and the FM21-Cheat-Table reads live player data (CA/PA/attributes) with no anti-tamper blocker. See [docs/phase0-feasibility.md](docs/phase0-feasibility.md) for details.

**Phase 1 in progress** — `scripts/lua/dump_state.lua` reads every field the base table exposes for the currently-selected player/club/staff and serializes it to JSON (generated from `fm.CT` itself, see `cheat-table/parse_ct.js` + `cheat-table/generate_dump_lua.js`). It is now **verified live** against a real save, field-by-field against the game's own UI — doing so turned up a silent bug where Cheat Engine stores pointer offsets in reverse order, which had been nil-ing out every name and contract field.

`scripts/lua/dump_squad.lua` reads a whole squad rather than just the selection: the senior squad is a `std::vector<Player*>`, and reading it via its header gives the exact squad — **verified live at 23/23 players, every record complete**. Nothing in memory points at that header and it's a fresh allocation each launch, so `scripts/lua/locate_vector.lua` re-derives it from the live selection; that now **reproduces across a cold restart**, returning the identical squad against a completely different heap layout. Staff reads are verified too (all 83 fields against a real coach).

A pointer scan produced 27 candidate static paths to the header, and **none survived a restart** — checked against a confirmed-live target, so it's a clean negative rather than a missing-structure artifact. A static path would be an optimisation, not a blocker.

Club reads are verified too — all 30 fields against a real club page. The hook needs both the `Current Club` script enabled *and* a club screen visited afterwards, which is why it read 0 for two sessions. Usefully, it retargets to whichever club you view, so opposition finances and facilities are readable, not just our own.

Fixtures, league tables and the transfer shortlist aren't covered at all, so **Phase 1's exit criterion is not met.** See [TODO.md](TODO.md) for the live work queue and [docs/phase1-notes.md](docs/phase1-notes.md) for the memory structures and tooling.

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
