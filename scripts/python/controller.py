"""Phase 4 stub: orchestration loop.

Target shape (see PLAN.md Phase 4):
    1. Trigger a state dump (via the Cheat Engine Lua bridge, scripts/lua/dump_state.lua)
    2. Package that state into a prompt for a "manager" model, using the full
       or restricted dataset depending on the active mode (cheat/human)
    3. Parse the manager's decision into structured actions
    4. Execute those actions through the Phase 2/3 write layer (scripts/lua/actions.lua)

Mode switching (cheat vs human) is a single config flag once Phase 5 lands.
Model-agnostic: each manager model plugs in behind a thin adapter sharing a
common JSON-state-in/JSON-decision-out contract, so saves can be run/replayed
across different models under identical conditions.

Not yet implemented — depends on Phase 1 (read) and Phase 2 (write) working
via a socket/pipe bridge to Cheat Engine's Lua engine, neither of which exist
yet. Phase 0 (env + attach) must pass first.
"""


def run_loop(mode: str = "cheat") -> None:
    raise NotImplementedError("run_loop: not yet implemented — see PLAN.md Phase 4")


if __name__ == "__main__":
    run_loop()
