-- Phase 1 stub: full-save JSON state dump, run inside Cheat Engine attached to fm.exe.
--
-- Target shape (see PLAN.md Phase 1):
--   dump_state("full")       -> every field, unmasked (cheat mode)
--   dump_state("restricted") -> same structure, gated by FM's "known-to-user" flags (human mode)
--
-- Not yet implemented — depends on the pointers found once the cheat table
-- (cheat-table/) is extended to walk the full squad/club/competition lists,
-- not just the single selected-player/club/staff pointers the base table exposes.

function dump_state(mode)
  mode = mode or "full"
  error("dump_state: not yet implemented — Phase 0 (attach + base table) must pass first")
end
