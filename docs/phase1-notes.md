# Phase 1 — Progress Notes

## What's done (no live game/CE session needed)

`scripts/lua/dump_state.lua` is now a real, generated script instead of a stub. It reads every field the vendored `fm.CT` table exposes for the **currently-selected** player, club, and staff member, and serializes it to JSON via `dump_state()` / `dump_state_json()` / `dump_state_to_file(path)`.

It was generated, not hand-written, to avoid transcription errors:

1. `cheat-table/parse_ct.js` — parses `fm.CT`'s XML and extracts every leaf data field (description breadcrumb, symbol, pointer-offset chain, variable type) into `cheat-table/fields.json`. Found 106 player fields, 30 club fields, 83 staff fields.
2. `cheat-table/generate_dump_lua.js` — turns `fields.json` into `scripts/lua/dump_state.lua`: a generic pointer-chain resolver + type-aware reader + minimal JSON encoder (Cheat Engine's Lua has no built-in JSON lib), driven by the extracted field tables.

Regenerate with `node cheat-table/parse_ct.js && node cheat-table/generate_dump_lua.js` if `fm.CT` ever changes.

## What's NOT done / blocked

**This has never been run against a live game.** Computer-use / desktop control access couldn't be approved in this session ("can't be approved during a scheduled run" — the approval dialog needs you present to click it), so nothing here has touched Cheat Engine or FM21 directly. Treat `dump_state.lua` as a strong first draft, not verified output.

When you're back at the machine, two things to check:

1. **Load `dump_state.lua` into the CE Lua Engine and run `dump_state_json()`** (Cheat Engine → main menu → hamburger/Table → "Lua Engine" or Ctrl+Alt+L, paste the file contents or `dofile()` it, then call the function from the console). Needs the base table's `-----[==Features==]-----` script active first, same as before, plus a player/club/staff actually selected in-game.
2. **String fields are the most likely thing to be wrong** — the offset chains for Name fields (First Name, Last Name, Full Name, club/nationality names) involve 2-3 levels of pointer indirection, and I don't know whether FM stores those as plain ASCII/UTF-8 buffers or something else (length-prefixed, wide-char). If those come back empty or garbled, that's the thing to debug first — everything else (CA, PA, attributes, positions, personality, contract fields) is single-level pointer math and much more likely to just work.

**The full-squad walk is still not started.** `dump_state.lua` only ever reads the one player/club/staff that's currently selected in FM21 — same limitation the base table always had. Getting every player in the squad in one JSON dump (the actual Phase 1 exit criterion) needs the squad-list array's pointer, which nobody has published for FM21. That requires live AOB/value scanning in Cheat Engine — genuinely can't be done without you at the keyboard (or granting computer-use access while present).

### Squad-array scan plan (for next live session)

Standard technique for finding a backing array of object pointers when you already have known object addresses:

1. With `-----[==Features==]-----` active, click through 2-3 different players in the squad screen, and after each, read the resolved `pCurrentPlayer` pointer value (the "pPlayer" table entry, or `dump_current_player()`'s raw address) — note down 2-3 real player addresses (e.g. Player A, Player B).
2. In CE's main scanner (not the Lua console), do a **new scan**, Value Type **"Array of byte"** or **"8 Bytes"**, Scan Type **Exact Value**, entering Player A's address as the value (hex), scanning **all writable memory**. This finds every place in memory holding a pointer to Player A — one of them should be inside the squad-list's backing array.
3. Repeat for Player B as a fresh scan (or cross-reference): the squad array will hold pointers to *both* A and B, close together in memory (typically 8 bytes apart per slot, sometimes with padding) — the results list should reveal a run of consecutive addresses when eyeballed, distinct from scattered single hits elsewhere (UI caches, undo buffers, etc.).
4. Once that array region is identified, note its start address and stride (bytes between consecutive pointer slots), and how the count is stored (usually a 4-byte count field near the array pointer, common in engine "dynamic array" containers). Add these as new symbols in `fm.CT` (or a new script alongside it) and extend `dump_state.lua` to loop `count` times over the array, applying the existing `FIELDS.CurrentPlayer` offset table to each resolved player pointer instead of just `pCurrentPlayer`.

This is genuinely exploratory — the exact container shape (raw array vs. linked structure) won't be known until step 2-3 turn up real results.
