# Session Log — 2026-09-09 (agentic strategy + cost baseline)

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 4 orchestration / experiment prerequisites
- **Starting point:** Phase 4's end-to-end lineup loop worked, but the `tools` strategy had never run and decision cost had only been logged, not analysed; see `2026-08-16-closing-the-loop.md`.
- **Access available this session:** full desktop/filesystem and local Ollama; FM21 was not running.

## What did it do?

1. Read `CLAUDE.md`, `TODO.md`, `PLAN.md`, the latest session log, and manager setup docs before changing code.
2. Ran the previously untested agentic path against `data/snapshots/squad_live.json`:
   `node scripts/manager/pick_lineup.js --mode cheat --model qwen3:8b --strategy tools --snapshot data/snapshots/squad_live.json`.
3. The tools run returned a valid XI on its first attempt and logged normally: 2489 input / 162 output tokens, 4.063 s decision latency after model warm-up.
4. Added `scripts/manager/analyse_costs.js`, a zero-dependency summary of `data/logs/decisions.jsonl` grouped by model/strategy.
5. Updated `TODO.md` to close the two now-verified Phase 4 queue items.

## Did it achieve its goals?

**Yes for both bounded goals.** The `tools` code path is no longer untested, and the existing decision log now has a repeatable cost-analysis command instead of hand-calculated numbers.

Current evidence from successful Qwen one-shot calls: 2260 average input tokens, 226 average output tokens, 5.09 s average decision latency. The one verified full model loop in the log took 85.77 s. The first tools sample is 2489 / 162 tokens and 4.06 s; one sample is not enough to compare strategies statistically.

## Why did it do what it did?

The latest session explicitly ranked exercising `tools` and analysing cost immediately behind advancing the game. FM21 was closed, so live date/advance work could not be verified, while these two tasks were fully testable against the preserved snapshot and local model. This closes known untested code before adding another layer.

The analyser reports observed runtime/token cost rather than pretending local Ollama tokens have a meaningful API-dollar price. Hosted-model pricing can be layered on later when a second provider exists.

## What did it learn?

- Qwen3:8b can complete the repository's real `tools` strategy successfully; the prior warning that small models are unreliable at multi-turn tools is a caution, not a demonstrated failure for this event.
- On this first sample, tools did not impose an obvious latency penalty versus one-shot (4.06 s vs 5.09 s successful one-shot average), but the sample size is far too small for a conclusion.

## What went wrong?

- FM21 was not running, so the real frontier from the previous session — detecting that the in-game date/time advanced and then progressing the save — could not be live-tested in this block.
- The repo already contained unrelated untracked work (`scripts/vision/capture.ps1` and a cheat-table file). It was deliberately left untouched and must not be swept into this commit.
- One historical one-shot log row is a transport failure (`fetch failed`) and another is an invalid duplicate-player decision. The analyser keeps these visible instead of filtering them out of the usable-rate denominator.

---

## Next session should probably

1. Start from the advance-game frontier: establish a reliable signal that a Continue action moved game time (date OCR, next-opponent change, or another UI-visible invariant), then wire the smallest safe advance primitive around it.
2. Repeat `--strategy tools` enough times to estimate first-try validity rather than relying on one successful sample.
3. Add a second provider/model only after the event loop can advance through more than one decision point; that remains Phase 4's outstanding cross-model criterion.
