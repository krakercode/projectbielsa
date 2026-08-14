-- Phase 2 stub: write-layer action API, run inside Cheat Engine attached to fm.exe.
--
-- Target shape (see PLAN.md Phase 2):
--   set_lineup(player_ids_by_position)
--   set_tactic(tactic_def)
--   offer_contract(player_id, terms)
--   bid_for_player(player_id, amount)
--
-- Actions that can't be done via direct memory writes (things that trigger
-- game logic/UI flows, e.g. transfer negotiations, press conferences) will
-- need a coordinate-based input-simulation fallback instead.
--
-- Not yet implemented — depends on Phase 1 read access to confirm which
-- fields are safely writable.

function set_lineup(player_ids_by_position)
  error("set_lineup: not yet implemented")
end

function set_tactic(tactic_def)
  error("set_tactic: not yet implemented")
end
