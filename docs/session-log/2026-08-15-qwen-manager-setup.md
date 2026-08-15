# Session Log — 2026-08-15 (Qwen manager stack)

## Session metadata

- **Date:** 2026-08-15
- **Phase(s) touched:** Phase 4 (orchestration/adapter), Phase 5 (mode filtering — placeholder only)
- **Starting point:** Read layer working for players/squads/staff/clubs; league table and fixtures unsolved after five approaches; **no model integration of any kind existed**. See `docs/session-log/2026-08-15-pointer-validation.md`.
- **Access available this session:** Full desktop; FM21 and CE running; internet for package install.

## What did it do?

1. Checked the machine: RTX 2080 (8 GB VRAM), 16 GB RAM, C: 20 GB free / D: 3 TB free, Node 24 present, **Python absent** (Windows Store stub only), no Ollama, no Docker.
2. Installed **Ollama 0.32.13** via `winget install Ollama.Ollama` (official GitHub release, installer hash verified by winget).
3. Set `OLLAMA_MODELS=D:\ollama-models` as a persistent user env var **before** pulling anything — C: has only 20 GB free and models are ~5 GB each.
4. Pulled `qwen3:8b` (5.2 GB).
5. Built `scripts/manager/`, zero npm dependencies:
   - `provider.js` — transport + adapter contract (`decide()` → `DecisionResult`), `OllamaProvider`, stubbed `ClaudeProvider`.
   - `squad_state.js` — scale conversion, compaction, and the cheat/human filter point.
   - `pick_lineup.js` — the first decision event, with validation and JSONL decision logging.
   - `profiles/pragmatic.json` — manager profile.
6. Ran it live in both modes. Wrote `docs/manager-setup.md` as the durable operating/handoff reference.

## Did it achieve its goals?

Goal was "install everything we'll need and get Qwen running." **Yes**, and further than that — a complete read-only decision loop runs end to end.

Evidence, cheat mode, ~5.9 s, 2284 in / 250 out tokens, validation passed:

```
4-2-3-1
GK  Emiliano Martínez     DC Tyrone Mings      DC Ezri Konsa
DR  Matty Cash            DL Matthew Targett
MC  John McGinn           MC Jack Grealish     AMC Ross Barkley
AML Anwar El Ghazi        AMR Mahmoud Hassan   ST  Ollie Watkins
```

That is close to Villa's real 2020-21 first-choice XI, from an 8B model, off a squad dump we extracted from memory ourselves.

## Why did it do what it did?

- **Node, not Python** (PLAN.md says Python). Python isn't installed; Node 24 is and the repo already uses it. Recorded as a deviation in `docs/manager-setup.md` rather than silently substituted.
- **`oneshot` strategy for Qwen, not the agentic tool loop** the design doc specifies. 8B models are unreliable at multi-turn tool calling. The loop *is* implemented; the strategy used is recorded on every result so a tool-loop run can never be silently compared against a one-shot run.
- **Compaction before anything else.** Raw `squad.json` is 43 KB (12–15k tokens) for 23 players. Compacted to 3.2 KB (~800 tokens) via summary/detail split. The design doc predicted this would be needed; it turned out to be mandatory, not optional, on an 8B.
- **Thinking disabled.** Qwen3 defaults to emitting long `<think>` traces, which on an 8B is minutes per call.
- **Model store on D:** rather than accept the default on a nearly-full C:.

## What did it learn?

- **Node's global `fetch` enforces a 300 s headers timeout that can't be changed without adding undici.** A cold 8B with thinking on exceeds it, and it surfaces as a bare `fetch failed`. Fixed by using `node:http` directly. This cost the first live run.
- **Qwen3 thinks by default via Ollama**, and `think: false` is the switch.
- **Warm the model separately.** Cold load is ~14 s of the measured time; without a warm call the first run of a session looks far slower than the model actually is.
- **Measured performance**: ~5–6 s per `pick_lineup`, well inside anything the eval needs.
- **The observation budget from PLAN.md is a practical necessity, not just a fairness device.** An 8B cannot usefully consume a full squad dump. Fairness and feasibility point the same way, which is a good sign the design is right.

### An observation, heavily caveated

Human mode produced a *different and clearly worse* XI — two left-backs, Watkins pushed wide, Keinan Davis (CA 113) starting ahead of him at striker.

That is the exact signal the experiment exists to detect. It is **not a result**: n=1, temperature 0.4, and the masking is an acknowledged placeholder. Recorded because it is encouraging about the pipeline, not because it means anything yet.

## What went wrong?

- **First live run failed** at 306 s with `fetch failed` — the undici timeout above. Diagnosed and fixed, but it was avoidable if I'd thought about cold-load time before running.
- **Human-mode masking is a placeholder and is a potential trap.** It buckets true CA into labels, which still leaks ordering a human wouldn't have. It's marked `masking: "placeholder-not-phase5"` in the emitted data and flagged in two docs, but someone could still run it and report the number. Phase 5's real question is untouched.
- **The agentic tool loop is written but never executed** — Qwen uses `oneshot`. So the `tools` path is untested code, which is exactly the failure mode this project has been bitten by before. Treat it as unverified until something runs it.
- **`ClaudeProvider` is a stub that throws.** There is currently no second model, so the cross-model comparison the plan needs cannot be run yet.

---

## Next session should probably

1. **Run the same task through a second model** — that's the plan's actual Phase 4 exit criterion ("same lineup-picking task through two adapters"). Cheapest path is a hosted model behind `ClaudeProvider`, or a second local model for a like-for-like local comparison.
2. **Exercise the `tools` strategy at least once** so it isn't untested code. Even a trivial `get_player` loop would do.
3. **Do not build more of the harness on the placeholder masking.** Either resolve Phase 5's question (FM's own known-to-user flags) or keep human mode explicitly labelled as a pipeline test.
4. Game side is unchanged and still open: league table (five approaches failed), fixtures, and the competition object — see `docs/session-log/2026-08-15-pointer-validation.md` and `TODO.md`.
