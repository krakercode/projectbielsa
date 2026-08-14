# Control Interface — How Models Actually Drive the Manager

This is a design proposal for Phase 4 (Orchestration Loop) and Phase 5 (Human-Mode Fidelity): the contract between "a game state exists in memory" and "a model decided to bench the left-back." It elaborates PLAN.md's one-line spec ("fixed JSON-state-in/JSON-decision-out contract with shared schema/prompt scaffold; each model plugs in behind a thin adapter") into something concrete enough to build against.

Nothing here has been built or tested — this is the plan to build from once Phase 1/2 (full-squad read/write) exist. Where it disagrees with PLAN.md's literal wording, the disagreement is called out explicitly with a reason, not silently substituted.

## The core design choice: agentic tool use, not a single JSON blob

PLAN.md's original phrasing — "JSON-state-in/JSON-decision-out" — suggests one big call: dump the whole world into a prompt, get one JSON decision back. That's simple to make model-agnostic, but it has real costs:

- **Token bloat.** A full squad + finances + fixtures + shortlist dump on every decision, even "pick the lineup," burns huge context for data the model won't use (nobody needs contract-expiry dates to pick a back four).
- **No selective lookup.** A human manager glances at one player's fitness before subbing them; a flat dump forces you to either include everything up front or not have it.
- **Doesn't match how good agentic models actually perform.** Claude (and GPT-class models) are trained for tool-calling loops — give them read/write tools and a goal, let them pull what they need.

**Recommendation: model the interaction as an agentic tool-use loop, not a single structured call.** Concretely, for each "decision event" (see below), the controller:

1. Gives the model a **system prompt** = manager profile + house rules + current mode (cheat/human) + what event this is.
2. Gives it a **read-tool set** scoped to that event (get_squad, get_player, get_fixtures, ...).
3. Gives it a **write-tool set** scoped to that event (set_lineup, offer_contract, ...).
4. Runs the loop until the model stops calling tools — it reads what it needs, then acts.

This is exactly the Tool Runner pattern (`client.beta.messages.tool_runner` for Claude) rather than a single `messages.create()` call. The **portable, model-agnostic part is the tool schemas** (JSON Schema, provider-neutral) and the event/prompt scaffold — not the specific loop-driving code, which is a thin per-model adapter (see below). This satisfies the "shared schema/prompt scaffold, thin per-model adapter" requirement in spirit while getting real agentic behavior instead of forcing every model to reason from one giant undifferentiated blob.

## Decision events, not one monolithic contract

Rather than "the" manager decision, there are several distinct decision *types*, each firing on a different trigger, each needing a different slice of state and a different action vocabulary:

| Event | Fires when | Needs (read) | Can do (write) |
|---|---|---|---|
| `pick_lineup` | Before a fixture | Squad (fitness/morale/form), tactic, opponent scouting, upcoming fixture congestion | `set_lineup`, `set_captain` |
| `set_tactic` | Season start / after a bad run | Squad, recent results, opponent style | `set_tactic` (formation, roles, mentality, instructions) |
| `transfer_decision` | Transfer window, scout report in | Shortlist, finances, squad needs/gaps, player being considered | `bid_for_player`, `offer_contract`, `reject_shortlist_player` |
| `in_match` | Live, each in-game "decision point" | Live score/minute/momentum, player conditions, bench | `make_substitution`, `set_mentality`, `give_team_talk`, `touchline_shout` |

Each event type gets its own **prompt scaffold** (a template: manager profile + house rules + event-specific framing) and its own **tool subset**. This keeps each call's context small and keeps the model from being handed 15 write tools when only 2 are relevant.

## Read tools — the state side

Read tools are thin wrappers around the Phase 1/4 controller's bridge to the Cheat Engine Lua side (`dump_state.lua` today only covers the currently-selected player/club/staff; Phase 1's still-open squad-array work is what lets `get_squad()` return every player instead of one). Proposed initial set:

- `get_squad()` → array of players (id, name, position, fitness, morale, condition, contract status — full or masked per mode)
- `get_player(player_id)` → full detail on one player (attributes, personality, injury history)
- `get_club_finances()` → balance, wage budget, transfer budget
- `get_fixtures(range)` → upcoming fixtures, congestion, opponent form
- `get_shortlist()` → scouted transfer targets with scout confidence
- `get_tactic()` → current formation/roles/instructions
- `get_live_match_state()` → (Phase 3, once found) score, minute, momentum, live ratings — in-match event only

**This is exactly where cheat/human mode plugs in**, per PLAN.md's original design — the write side is identical in both modes; only reads are filtered:

- **Cheat mode**: these return exactly what `dump_state.lua` reads off raw memory — true CA/PA, exact morale numbers, hidden personality traits.
- **Human mode**: the same tool, same schema, but every value gated by whether FM's own game state marks it "known" to the human manager (Phase 5's still-open question of whether that's read from FM's own internal flags or reimplemented). A scouted player's CA might come back as `{"range": [130, 145], "confidence": "medium"}` instead of `142`. The model never needs to know *how* the masking works — it just gets ranges instead of numbers when the tool call answers that way. The system prompt tells it which mode is active so it calibrates its confidence accordingly, but the filtering itself is invisible plumbing in the Python tool implementation, not something the model has to reason about.

This means Phase 5 is additive to this design, not a redesign: swapping cheat↔human mode is a config flag that changes what the *read tools* return, full stop.

## Write tools — the action side, with validation

Write tools map directly onto the Phase 2/3 action-API stubs already sketched in `scripts/lua/actions.lua` (`set_lineup`, `set_tactic`) plus the ones PLAN.md names but haven't been stubbed yet (`offer_contract`, `bid_for_player`, substitution/mentality/shout for Phase 3).

**Every write tool validates before touching the game.** Models hallucinate — a `bid_for_player` call naming a player not on the shortlist, or a `set_lineup` call naming a player not in the currently selected club's squad, must fail cleanly rather than doing something undefined. Per standard tool-use error handling: return `{"type": "tool_result", ..., "is_error": true, "content": "player_id 4471 is not in the current squad"}` rather than either crashing or silently no-opping — the model sees the error and can self-correct within the same loop, and it's logged either way.

```json
{
  "name": "set_lineup",
  "description": "Set the starting XI and formation positions for the next fixture. Player IDs must come from a get_squad() call in this session — do not guess IDs.",
  "input_schema": {
    "type": "object",
    "properties": {
      "starting_xi": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "player_id": {"type": "integer"},
            "position": {"type": "string", "description": "e.g. GK, DC, DM, AMC, ST"}
          },
          "required": ["player_id", "position"]
        },
        "minItems": 11,
        "maxItems": 11
      },
      "captain_id": {"type": "integer"}
    },
    "required": ["starting_xi"]
  }
}
```

Note the description is written to be *prescriptive about when/how to call it*, not just what it does — per current Claude tool-use guidance, tool triggering and correct-use rate both improve measurably from explicit "do this, not that" language in the description, not just the system prompt.

## The manager profile — this is how objectives/parameters get tuned

This directly answers "how can we refine their objectives, parameters" — it's a **structured config, separate from game state, injected into the system prompt**:

```yaml
# manager_profiles/pragmatic.yaml
name: "Pragmatic Pragmatist"
risk_tolerance: medium       # low | medium | high — squad rotation, gamble signings, tactical gambles
tactical_philosophy: |
  Favors compact defensive shape and fast transitions over sustained possession.
  Willing to sacrifice possession share for defensive solidity against stronger sides.
transfer_strategy:
  aggressiveness: medium      # how readily it bids above valuation / breaks wage structure
  priorities: [squad_depth, youth_development]   # vs. e.g. [marquee_signings, immediate_first_team]
squad_building:
  rotation_policy: heavy      # heavy | light — how much it rotates for fixture congestion
  youth_trust: medium         # willingness to start academy players
communication:
  verbosity: low              # how much reasoning it surfaces vs just acting
  explain_reasoning: true     # whether decision logs include a rationale
```

This gets rendered into a template block in the system prompt (not the model's training-time persona — an explicit, swappable, versioned config). Running the same save under two different profiles (aggressive-spender vs. thrifty-builder) with the same model is how you'd actually test whether the *tactics* differ meaningfully vs. just noise — and running the same profile under two different *models* is how you'd satisfy the plan's "run the same lineup-picking task through two model adapters" requirement. These are orthogonal knobs: profile is "what kind of manager," model is "which brain."

**Where this sits in the prompt** matters for caching (see below): manager profile + house rules + tool definitions are stable for an entire save/season and belong in the cached prefix; only the per-decision event framing and live state go after the cache breakpoint.

## Persistent memory — because football management is long-horizon

A single decision call is stateless by default, but a manager's real decisions depend on things the game itself won't hand back on request: "I promised this player first-team football," "we're building toward a back-three by January," "this signing was a mistake, don't repeat it." A fresh call every matchday with no memory of *why* past decisions were made will make the manager incoherent over a season.

**Recommendation: give the model the memory tool** (`memory_20250818`, client-executed — Claude reads/writes files in a fixed directory you back with real storage). Point it at `data/memory/<save_id>/` in this repo (already gitignored under `data/`). Concretely:

- Before a `transfer_decision` or `set_tactic` event, the model can check its own notes for prior commitments/strategy.
- After a significant decision, it writes a short update.
- This is *separate* from the decision log (below) — the memory is the model's own working notes for itself; the log is an external audit trail of what happened and why.

This is the cleanest fit for "long-horizon coherence" without inventing a bespoke mechanism — it's an existing, documented Anthropic tool, not something we'd have to build.

## Model-agnostic adapter layer

The plan's actual requirement: "each model plugs in behind a thin adapter; config selects which model/API runs a given save/season." Given the tool-use design above, this is a genuinely thin layer:

```python
class ManagerAdapter(Protocol):
    def decide(self, event_type: str, system_prompt: str, tools: list[dict],
               initial_context: str) -> DecisionResult:
        """Runs the agentic loop for one decision event. Returns the tool calls
        made, the final reasoning (if the model surfaced any), and token/cost usage."""

class ClaudeAdapter(ManagerAdapter):
    # client.beta.messages.tool_runner(...) — SDK owns the loop
    ...

class OtherProviderAdapter(ManagerAdapter):
    # manual while stop_reason == "tool_calls" loop, translating our
    # provider-neutral JSON-Schema tool defs into that provider's function-call format
    ...
```

Because tool schemas are plain JSON Schema (not an Anthropic-specific format), the *actions* are portable across providers — most agentic-capable LLM APIs use structurally similar function-calling. The adapter's job is just: drive that provider's loop, translate tool-call/tool-result shapes, and return a common `DecisionResult`. Config (a YAML or env var: `manager_model: claude-opus-5`) selects the adapter; the event/prompt/tool-schema layer above it never changes.

## Logging and replay

Every decision gets logged — this is both an audit trail and the substrate for the "same task, different models/profiles" comparison PLAN.md asks for:

```json
{
  "event_type": "pick_lineup",
  "game_date": "2027-03-14",
  "save_id": "aston_villa_save_1",
  "mode": "cheat",
  "manager_profile": "pragmatic",
  "model": "claude-opus-5",
  "state_snapshot_id": "snap_20270314_1",
  "tool_calls": [
    {"tool": "get_squad", "result_summary": "24 players returned"},
    {"tool": "get_fixtures", "args": {"range": "next_3"}},
    {"tool": "set_lineup", "args": {"starting_xi": [...], "captain_id": 4412}}
  ],
  "reasoning_summary": "Rotated the back four for fixture congestion; kept the front three unchanged after a strong result.",
  "tokens": {"input": 3200, "output": 540},
  "wall_clock_ms": 4100
}
```

Stored as JSON Lines under `data/logs/` (already in `.gitignore`). This is what "log each decision alongside the state that prompted it" (PLAN.md, Phase 4) actually means concretely — and it's the input to any later "did model A's transfer strategy actually differ from model B's" analysis.

## A worked example: `pick_lineup` end to end

1. Controller detects a fixture is 24h out (or is asked directly). Fires `pick_lineup`.
2. Builds system prompt: manager profile (`pragmatic.yaml` rendered) + house rules + "You are picking the starting XI for the next fixture. Mode: cheat." Tools: `get_squad`, `get_player`, `get_fixtures`, `get_tactic`, `set_lineup`, `set_captain`.
3. Model calls `get_squad()` — reads fitness/form/morale for all 24 players. Calls `get_fixtures(range="next_3")` — sees a midweek cup tie coming right after, decides to rest two starters. Maybe calls `get_player(id)` on an injury-doubt to check fitness specifically.
4. Model calls `set_lineup({starting_xi: [...], captain_id: ...})`.
5. Controller's write-tool wrapper validates the 11 player IDs are real squad members, then calls the Phase 2 Lua `set_lineup()` and re-reads the tactics screen to confirm it took.
6. Tool result returned to the model: success + the confirmed lineup as read back.
7. Model either stops (loop ends, `stop_reason: end_turn`) or, if something looks wrong on the confirm-read, adjusts.
8. Controller logs the full exchange, including which memory notes (if any) were consulted.

## Open questions / risks specific to this design

- **In-match latency.** Live subs need near-real-time decisions during a 90-minute match — a slow `xhigh`-effort call is the wrong tool there. Likely needs a faster/cheaper model or lower effort specifically for `in_match` events, with `pick_lineup`/`transfer_decision` allowed to think harder since they're not time-critical. This is a real tension the plan doesn't currently resolve and is worth deciding once Phase 3 (live match data) actually exists.
- **Context cost of `get_squad()` on a large squad.** 25-30 players with full attribute breakdowns is not small. Worth designing `get_squad()` to return a compact summary by default (name, position, fitness, morale, one-line form) with `get_player(id)` for the deep-dive, rather than dumping every attribute for every player on every call.
- **Human-mode masking is still Phase 5's open question** (FM's own "known" flags vs. reimplementing the masking logic) — this design doesn't resolve that, it just defines where the answer plugs in (inside the read-tool implementations).
- **Prompt caching payoff is real here**: manager profile + house rules + tool defs are stable for a whole save, and per-decision live state is what varies — that's exactly the shape prompt caching wants (stable prefix, volatile suffix), worth wiring up once real API calls exist rather than as an afterthought.
