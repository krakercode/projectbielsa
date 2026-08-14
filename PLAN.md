# FM21 AI Manager — Project Plan

Goal: Claude plays Football Manager 2021 — both between matches (transfers, tactics, training, squad selection) and live during matches (subs, in-match tactics, touchline shouts) — with two selectable data modes:
- Cheat mode — full memory access, sees everything including hidden attributes, true CA/PA, board finances, hidden morale/condition values.
- Human mode — same action capabilities, but the data fed to Claude is filtered to only what an actual manager would know: scouted/revealed attribute ranges, not hidden true values.

Foundation: FM21 is frozen (no more patches), so tooling built against it won't break under our feet. The base technique is Cheat Engine's Lua scripting layer attaching to fm.exe — this is what FMRTE, FMSE21, and the existing xAranaktu/FM21-Cheat-Table are all built on. That table already proves pointers exist and are findable for the current player/club/staff in a save.

## Phase 0 — Environment & Feasibility Check
- Install FM21 (Steam, patched to 21.4.0 — the version FMRTE/cheat tables target), Cheat Engine 7.2, and the FM21-Cheat-Table.
- Confirm the table's pointers still resolve on our actual game build (Steam sometimes drifts slightly from the version a table was built against).
- Confirm FM21's anti-tamper protections (documented as present, blocking some tools) don't prevent Cheat Engine from attaching. If they do, this is a hard blocker to resolve before anything else — likely means using a DBVM-capable CE build or an alternate attach method.
- Exit criterion: can attach CE to a running FM21 save and read a known value (e.g. current player's CA) live.

## Phase 1 — Data Layer: Full-Squad Read Access (Between-Match)
- Existing table only exposes the currently selected player/club/staff pointer. Need to extend this to walk the full squad list, full club list, and competition/league tables — the FM24/23 cheat tables (still being actively maintained) show the AOB-scan technique for finding table-start/table-end pointers; same method applies to FM21.
- Build a Lua script that, on demand, dumps a structured JSON snapshot: full squad (attributes, contracts, morale, injuries, hidden personality traits), tactics screen state, transfer market shortlist, club finances, upcoming fixtures.
- Two dump modes from day one: full (every field, unmasked — cheat mode source data) and restricted (same structure, but every attribute/value gated by whether FM's own game state marks it as "known" to the human manager — see Phase 5).
- Exit criterion: one script call produces a clean JSON snapshot of an entire save's key state.

## Phase 2 — Write Layer: Between-Match Actions
- Identify which actions are writable directly via memory (squad selection, tactic sliders/roles, training schedule, contract terms) vs which realistically need simulated clicks because they trigger game logic/UI flows that don't have a simple memory equivalent (transfer negotiations, press conferences).
- Build a thin action API: set_lineup(), set_tactic(), offer_contract(), bid_for_player(), etc. Actions that can't be done via memory fall back to coordinate-based input simulation as a last resort.
- Exit criterion: Claude can change a lineup and a tactic in a live save via script, confirmed by re-reading state.

## Phase 3 — In-Match Data & Actions (the hard, unsolved part)
- No existing tool publishes pointers for live match state — score, clock, momentum, live ratings — this is genuinely new reverse-engineering work.
- Use Cheat Engine's own scanning tools (value search, AOB scan) during a live match to locate score/minute/possession/rating pointers, following the same method the FM23/24 community used for their club/person tables.
- Once located, add these to the cheat table and extend the JSON dump to cover live match state.
- Test whether in-match actions (subs, mentality change, touchline shout, role tweak) are writable via memory mid-match, or require simulated clicks on the match UI.
- Exit criterion: can read live score/minute and make at least one in-match change (e.g. a substitution) programmatically during a match.

## Phase 4 — Orchestration Loop
- A controller script (Python, talking to Cheat Engine's Lua engine via a socket/pipe) that: (1) polls or event-triggers a state dump, (2) packages that state into a prompt for a "manager" using the full or restricted dataset depending on active mode, (3) parses the manager's decision into structured actions, (4) executes those actions through the Phase 2/3 write layer.
- Mode switching is a single config flag.
- Exit criterion: one full loop — state → decision → action — runs end to end for a between-match event (e.g. picking a lineup for the next fixture) without manual intervention.
- Model-agnostic manager interface: fixed JSON-state-in/JSON-decision-out contract with shared schema/prompt scaffold; each model plugs in behind a thin adapter; config selects which model/API runs a given save/season so saves can be replayed or run in parallel across models under identical conditions. Log each decision alongside the state that prompted it.
- Exit criterion: same lineup-picking task runs successfully through at least two different models' adapters with no changes to the surrounding loop.

## Phase 5 — Human-Mode Fidelity
- Human mode has to mirror FM's own knowledge model — attribute values genuinely uncertain until scouted, shown as ranges not exact numbers.
- Best approach: find FM's own internal "known-to-user" flags in memory and read those directly, making human mode authoritative.
- Fallback: reimplement FM's masking logic ourselves (scouting %, coach reports, match experience) as an approximation.
- Decide which approach after Phase 1 read access is working.

## Phase 6 — Testing & Calibration
- Run the same save under both modes side by side to check human mode isn't leaking hidden values.
- Tune how Claude is prompted as a manager — risk tolerance, communication style, how much reasoning to surface vs just act.
- Stress-test the in-match loop on a full 90 minutes before trusting it unattended.

## Open Risks
- FM21's anti-tamper protections could block Phase 0 outright — untested with our specific build.
- In-match pointers are genuinely unexplored territory; Phase 3 could take significantly longer than the others.
- Match-engine actions may resist memory writes even once state is readable.
- This sits in FM's single-player modding/cheat-tool space (same category as FMRTE) — not something SI officially supports, though it's a well-established hobbyist practice for single-player saves.

## Suggested Build Order
Phase 0 → Phase 1 → Phase 2 → Phase 4 (between-match loop working end to end, cheat mode only) → Phase 5 (add human mode) → Phase 3 → Phase 6.

Rationale: get a complete, working cheat-mode between-match loop first — highest-confidence path since groundwork already exists in the community. Add human-mode filtering once the pipeline is proven. Save the genuinely unsolved in-match work for once everything else is stable.

Note: this project is entirely single-player, offline modding of the user's own game save — no online/multiplayer interaction.
