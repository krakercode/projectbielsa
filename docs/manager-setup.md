# Manager Stack — Setup, Operation and Handoff

How a model actually gets asked to manage, what is installed, how to run it, and
what to watch out for. This is the durable reference; `docs/control-interface.md`
is the design it implements.

**Status: working end to end for one decision event (`pick_lineup`), read-only.**
No write layer exists, so decisions are produced, validated and logged but never
applied to the game.

---

## What's installed

| Piece | Detail |
| --- | --- |
| Ollama | 0.32.13, via `winget install Ollama.Ollama` (official GitHub release, hash verified) |
| Model | `qwen3:8b` (~5.2 GB on disk) |
| Model store | `D:\ollama-models` — **deliberately not the default**, C: has only ~20 GB free |
| Runtime | Node 24 (already present). No npm dependencies — everything uses Node built-ins |

`OLLAMA_MODELS=D:\ollama-models` is set as a **user environment variable**, so it
survives reboots. If models ever start landing on C:, that variable got lost.

## How Claude talks to Qwen

Plain HTTP to Ollama's local server. No SDK, no API key, no network egress.

```
Node controller  ──POST /api/chat──>  Ollama (127.0.0.1:11434)  ──>  qwen3:8b on the GPU
                 <──── JSON ────────
```

`scripts/manager/provider.js` owns the transport and implements the adapter
contract from the design doc: `decide({eventType, systemPrompt, initialContext,
tools, strategy})` returns a `DecisionResult` (tool calls, parsed decision,
reasoning, token counts, wall clock, error) regardless of which model ran.

Two strategies, and every result records which one was used:

- **`tools`** — the real agentic loop from the design doc: read tools, then act.
  Right for Claude-class models.
- **`oneshot`** — state supplied up front, one structured JSON reply. **This is
  what Qwen 8B currently uses.** Small models are unreliable at multi-turn tool
  calling. It is a fallback, not the design.

The `strategy` field exists so nobody can later compare a tool-loop run against a
one-shot run and treat them as the same condition.

## Running it

```bash
node scripts/manager/pick_lineup.js --mode cheat
node scripts/manager/pick_lineup.js --mode human
node scripts/manager/pick_lineup.js --dry-run          # print the prompt, call nothing
node scripts/manager/pick_lineup.js --model qwen3:8b --strategy oneshot
```

Flags: `--mode cheat|human`, `--model`, `--snapshot`, `--strategy`, `--profile`,
`--dry-run`. Exit code 2 means the model replied but the XI failed validation.

Every run appends to `data/logs/decisions.jsonl` (gitignored) with mode, model,
profile, strategy, decision, validation errors, tokens and wall clock — the
substrate for cross-model comparison.

Input is `data/snapshots/squad.json`, produced from the CE Lua Engine:

```
dofile([[C:\Users\User\Desktop\projectbielsa\scripts\lua\locate_vector.lua]])
locate_vector()
dump_squad_to_file(nil, "<header address it prints>")
```

## Measured behaviour (RTX 2080, 8 GB)

| | |
| --- | --- |
| Model load (cold) | ~14 s, then cached for 10 min via `keep_alive` |
| Inference, `pick_lineup` | ~5–6 s |
| Tokens | ~2,300 in / ~250 out |
| Prompt size | ~800 tokens of squad state |

## Gotchas — all of these were hit for real

**Node's `fetch` has a 300-second headers timeout you cannot change** without
adding undici as a dependency, and a cold 8B with thinking enabled blows straight
through it. It surfaces uselessly as `fetch failed`. The provider therefore uses
`node:http` directly. Don't "simplify" it back to `fetch`.

**Qwen3 thinks by default**, emitting thousands of tokens inside
`<think>...</think>` before answering. On an 8B that is minutes per call. The
provider sets `think: false`. If you enable it for a reasoning comparison, record
it — `provider.name` appends `+think` precisely so the log can't hide it.

**Attribute scales.** `dump_state.lua` emits FM's internal values on purpose.
Attributes are 1–100 internally, 1–20 on screen (`displayed = round(internal/5)`);
condition and fitness are 0–10000. `squad_state.js` converts at the presentation
boundary. A model shown raw "Dribbling 85" will reason about it as absurd.

**Context.** Raw `squad.json` is ~43 KB (12–15k tokens) for 23 players — too much
for an 8B to use well. `squad_state.js` compacts it to ~3.2 KB (~800 tokens) via
a summary/detail split. This is the design doc's own predicted problem, and it is
also why the **observation budget** in `PLAN.md` is a practical necessity and not
only a fairness mechanism.

**VRAM.** 8 GB fits a Q4 8B (~5 GB) plus KV cache at `num_ctx: 8192`. Raising
context materially will spill and slow to a crawl. 14B needs CPU offload; 30B+ is
not viable on this machine.

---

## The brief the model is given

Rendered in `pick_lineup.js` from a manager profile
(`scripts/manager/profiles/pragmatic.json`) plus house rules plus the active
mode. The current contract:

- Pick exactly 11 players, referenced by the numeric `id` from the supplied squad
- Exactly one goalkeeper
- Respect each player's listed positions
- Condition is a percentage; below 80% risks injury
- Reply with **only** a JSON object: `formation`, `starting_xi[{id, position}]`,
  `captain_id`, `reasoning`

Cheat mode tells it CA/PA are exact. Human mode tells it that it cannot see true
ability and must reason under uncertainty.

**Human-mode masking is a placeholder and is marked as such in the data**
(`masking: "placeholder-not-phase5"`). It buckets true CA into coarse labels,
which still leaks ordering a real manager would not have. It exists so the
pipeline can run end to end. **It must not be used for any published result** —
Phase 5's actual question (read FM's own known-to-user flags vs reimplement the
masking) is still open.

## Adding another model or another event

- **Another model behind the same interface**: implement a class with
  `name`, `health()` and `decide()`. `ClaudeProvider` in `provider.js` is a
  deliberate stub that throws — the Anthropic SDK and a key aren't set up yet.
  A hosted Qwen (DashScope, OpenRouter) is a base-URL change plus auth.
- **Another decision event** (`set_tactic`, `transfer_decision`): the prompt
  scaffold currently lives inside `pick_lineup.js` because there is exactly one
  event. Extract it to `prompts.js` when the second one lands, per the design
  doc's shared-scaffold requirement.

## Deviations from the plan, stated not smuggled

1. **Node, not Python.** `PLAN.md` says Python for the controller. Python is not
   installed here (Windows Store stub only); Node 24 is, and the repo already
   uses Node for `cheat-table/*.js`. Nothing in the design depends on the
   language — the portable part is the JSON-Schema tool definitions.
2. **JSON manager profiles, not YAML.** Same fields; avoids needing a YAML parser
   while the controller has zero dependencies.
3. **`oneshot` strategy for Qwen**, where the doc specifies an agentic tool loop
   for everything. Reason above; the loop is implemented and available.
