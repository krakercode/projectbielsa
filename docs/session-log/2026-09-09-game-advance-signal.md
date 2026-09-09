# Session log — authoritative game-time progress signal

## Session metadata

- **Date:** 2026-09-09
- **Phase(s) touched:** Phase 1 / Phase 4 orchestration
- **Starting point:** RTTI had reduced 1,934 date-like memory copies to 49 nearby class families, but no authoritative current-game-time owner had been proven.
- **Access available:** live FM21 process, read-only process-memory tools, UI input scripts.

## What changed

The advance signal is now proven and usable.

1. RTTI classification of the 49 candidate families found three vtables resolving to `.?AVGAME@@`.
2. One candidate date copy sat inside a live `GAME` object at heap address `0x63CE4480` in this process.
3. A full writable-memory pointer scan found a module-relative global pointing to that GAME object: **`fm.exe+0x7002EC8`**.
4. This is the durable root. The heap address is per-process and must not be reused after restart.
5. The live object currently uses vtable **`fm.exe+0x6531AA0`**, which RTTI resolves to `GAME`.
6. Three adjacent 32-bit fields at `GAME+0x90`, `GAME+0x94`, and `GAME+0x98` move when FM's visible date/time moves.
## Live proof

The signal was checked against visible UI time, not inferred from matching integers:

- `4 Oct 2020 21:15` → `07E4591D:07E45916:07E48516`
- `5 Oct 2020 08:00` → `07E47D1D:07E47D16:07E48516`
- `5 Oct 2020 09:00` → `07E4131E:07E41317:07E48516`
- `5 Oct 2020 15:15` → `07E41B1E:07E41B17:07E45D17`

The encoding is clearly **not monotonic**, so these values must not be treated as a sortable timestamp. The verified operation is only: **did the fingerprint change?** That is enough to prove FM advanced.

A control also behaved correctly: opening the next unread inbox item changed the UI but did **not** change the GAME fingerprint.

## New tooling

### `scripts/win/read_game_time.ps1`

Read-only helper which:

- resolves `fm.exe` base dynamically;
- follows `fm.exe+0x7002EC8`;
- validates that the target has one of the known `GAME` vtables;
- returns the three-field fingerprint as text or JSON.
### `scripts/manager/advance_until_progress.js`

Small safe advance primitive. It focuses FM, records the GAME fingerprint, then clicks only the fixed top-right navigation control (Inbox / Social Feed / Next Unread / Continue) until the fingerprint changes.

It does **not** answer mandatory prompts. If FM shows `MUST RESPOND`, clicking the top-right control cannot resolve it, so the script eventually returns `blocked/no progress` instead of making an unlogged decision.

This behaviour was verified live. At 5 Oct 2020 15:15 the script stopped on a mandatory Watford transfer offer for 17-year-old Aaron Ramsey. The fingerprint stayed unchanged across eight navigation clicks.

## Why this matters

The previous loop could choose and apply a lineup but could not prove the save had moved afterwards. That prevented any multi-decision scenario from running unattended.

The progress detector is now independent of OCR, Cheat Engine, heap addresses, and the exact visual page FM happens to be showing. The remaining orchestration problem is event dispatch: when time cannot move because FM requires a decision, identify that event and route it to the correct decision handler.

## What is still open

1. Add required-response classification/dispatch. The first real live case is a transfer offer.
2. Keep administrative/non-football prompts deterministic only where the policy is explicit (for example declining optional deadline-day media participation).
3. Route football decisions through the evaluated manager rather than silently choosing defaults.
4. After dispatch exists, run repeated advance → event → decision → action cycles and log every state transition.

## Validation run

- `powershell -File scripts/win/read_game_time.ps1 -AsJson` returned a validated GAME pointer and fingerprint.
- `node --check scripts/manager/advance_until_progress.js` passed.
- `advance_until_progress.js --max-clicks 8 --timeout-ms 15000` safely returned no-progress on the mandatory transfer offer.
