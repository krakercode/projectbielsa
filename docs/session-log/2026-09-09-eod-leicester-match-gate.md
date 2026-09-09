# Session Log — end-of-day Leicester match gate

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 4 orchestration; Phase 3 live-match preparation
- **Starting point:** press-conference flow had been completed and pushed as `9643151`; live save was immediately before Leicester.
- **End point:** final pre-kickoff team/tactics screen for Leicester, game not deliberately advanced into the match viewer.

## What was done after the press-conference commit

1. Continued the disposable live save using the authoritative `GAME` progress fingerprint.
2. Reached the Leicester match-day team-selection gate.
3. Ran the existing full lineup loop with `qwen3:8b` / pragmatic profile.
4. `run_decision.js` read 23 registered players, filtered to 19 available, obtained a valid XI, applied it through `set_lineup.js`, and verified all eleven slots from memory.
5. The verified XI was Martínez; Cash, Konsa, Mings, Targett; McGinn, Sanson, Grealish; Traoré, El Ghazi; Watkins.
6. The loop completed in about 101.5 s. The exact state/model output is already in the gitignored decision log/state snapshot.
7. A one-time UI validation identified the next stop as the pre-match **Tactical Meeting**.
8. Assistant tactical recommendations were deliberately **not** accepted. `set_tactic()` / roles / duties / OIs are not yet a verified model-controlled action path, so accepting those recommendations would silently delegate football decisions.
9. Navigated through the meeting toward final team selection while preserving the verified XI/tactic.
10. At end of day FM is on the final pre-kickoff tactics/team screen. Do not infer active controls from stale button objects alone; live UI generations can survive in memory.

## Phase 3 probe

The executable RTTI was indexed for the match lifecycle before entering the actual viewer. Durable primary vtables exist for:

- `GAME_MATCH`
- `GAME_MATCH_SESSION`
- `MATCH_SESSION@fmmatchviewer`
- `MATCH_SCORE_TIME_PANEL@fmmatchviewer`
- `GAME_MATCH_STATS`
- `GAME_MATCH_PLAYER_STATS`
- `GAME_MATCH_MANAGER`
- `MATCH_SESSION_MANAGER@fmmatchviewer`

Before the real match viewer instantiated, `GAME_MATCH`, `GAME_MATCH_SESSION`, `MATCH_SESSION`, and `MATCH_SCORE_TIME_PANEL` had no live primary instances. Historical `GAME_MATCH_STATS` / `GAME_MATCH_PLAYER_STATS` copies were present, and the match-session manager singleton was live. This gives the next session a clean before/after RTTI differential at kickoff.
## Cautions / next start

- The post-press match-day UI again demonstrated that raw `BUTTON` / `ICON_BUTTON` instances can be stale. Semantic state or behavioural verification must gate actions.
- Do not accept tactical-meeting assistant suggestions as a substitute for the model until the tactic/role/OI action interface exists.
- Next session: load this save, enter the Leicester match, immediately rescan the known match RTTI classes, and differential newly instantiated objects. Prioritise `MATCH_SCORE_TIME_PANEL`, `GAME_MATCH`, and `MATCH_SESSION` for clock/score state.
- Once a live score/time owner is found, repeat the existing rule: establish a restart-safe root or derivation path before promoting it into the evaluator.
