-- Phase 2 write layer -- MEMORY-WRITE path. Still unimplemented, and deliberately.
--
-- READ THIS BEFORE IMPLEMENTING ANYTHING HERE.
--
-- set_lineup IS implemented, but not here: see scripts/manager/set_lineup.js,
-- which drives FM's tactics UI and verifies the result by re-reading the
-- selection out of memory. It works end to end -- a two-position change applied
-- by script and confirmed both in memory and on screen (2026-08-16).
--
-- WHY THE WRITE LAYER IS NOT MEMORY-BASED
-- 1. PLAN.md requires the write layer to be UI-equivalent as a STRUCTURAL
--    property -- "not developer discipline ... one violation invalidates a run".
--    A drag on the tactics screen cannot violate that. A memory poke relies on
--    us never making a mistake, which is exactly the weaker guarantee PLAN.md
--    warns against.
-- 2. Changing a lineup triggers validation, role/duty assignment and tactical
--    familiarity. Writing a player reference into a slot risks a state the match
--    engine never agreed to -- a correctness problem, not only a fairness one.
-- 3. The authoritative selection store has not been found. Four hypotheses were
--    ruled out (see docs/session-log/2026-08-16-phase2-lineup-read.md): it is not
--    a field on the player record, not a packed UID array in positional order,
--    not a packed pointer array in positional order, and no contiguous positional
--    XI array exists at any stride. The eleven readable copies are UI models,
--    bulk-assembled by a system-DLL memcpy.
--
-- So a memory-write implementation is currently BLOCKED on locating the tactic
-- object, which is being pursued as separate work rather than as a blocker.
--
-- IF THAT CHANGES and a memory path becomes possible, it must still satisfy the
-- UI-equivalence contract by construction: only expose actions a human could take
-- through the UI (set a lineup, offer a contract, change a tactic), never raw
-- field pokes (CA, morale, budgets). Log every write for audit.

function set_lineup(player_ids_by_position)
  error("set_lineup: use scripts/manager/set_lineup.js -- the write layer is UI-driven, " ..
        "and the authoritative selection store is not located. See the notes at the " ..
        "top of this file before implementing a memory-write path.")
end

function set_tactic(tactic_def)
  error("set_tactic: not implemented. Same reasoning as set_lineup -- see the notes " ..
        "at the top of this file.")
end
