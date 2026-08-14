# Phase 0 — Environment & Feasibility Check

**Status: ✅ PASSED as of 2026-08-14.** Cheat Engine attached to `fm.exe` and the FM21-Cheat-Table's "Current Player" script read live data (CA, PA, and the rest of the player attribute block) off a real save, confirmed against Ezri Konsa's profile in-game. No anti-tamper blocker encountered. Phase 1 (full-squad read access) is next.

## Findings

| Requirement | Status | Notes |
|---|---|---|
| Football Manager 2021 | ✅ Installed | Steam app id `1263850`, installed at `D:\SteamLibrary\steamapps\common\Football Manager 2021`. `fm.exe` present. Build id `6682909` per Steam manifest (`appmanifest_1263850.acf`). No `EasyAntiCheat`/`BattlEye` binaries found in the install directory — good sign for Cheat Engine attach, but unconfirmed until actually tested against a running process. |
| FM21 patch version (21.4.0 expected) | ⚠️ Unconfirmed | Couldn't determine the in-game version string from the install directory alone. Steam shows this install as fully up to date (no pending update), so it's very likely 21.4.0 (the final patch SI shipped), but this should be confirmed from the in-game "About" / main menu screen. |
| Steam | ✅ Installed | Multiple library folders in use (`C:\Program Files (x86)\Steam`, `C:\Games\new steam`, `C:\Steam`, `D:\SteamLibrary`). FM21 lives in the `D:\SteamLibrary` one. |
| Cheat Engine | ❌ Not installed | No Cheat Engine install found anywhere on the `C:` or `D:` drives. Install the latest stable release; only fall back to 7.2 specifically if the table won't attach/resolve on it (see note below). |
| FM21-Cheat-Table (xAranaktu/FM21-Cheat-Table) | ✅ Downloaded | Cloned into `cheat-table/FM21-Cheat-Table/` (`fm.CT` + `changelog.txt`). Its README states it was **tested with Cheat Engine 7.2 on Win10 x64, Steam game version v21.3** — one version behind the v21.4.0 the plan assumed. Worth checking whether pointers still resolve on our v21.4.0-ish build once attach is tested. |
| Cheat Engine attach | ✅ Works | Attached to `00001D2C-fm.exe` cleanly. No anti-tamper block encountered. |
| Anti-tamper / attach test | ✅ Passed | `-----[==Features==]-----` script activated (allocates `pCurrentPlayer`/`pCurrentClub`/`pCurrentStaff`), "Current Player" child script activated, and CA/PA/attributes updated live in CE when selecting a player (Ezri Konsa) in-game. Confirms both attach and pointer resolution on our build. |

## What this means

The good news: FM21 itself is already installed and looks clean (no visible anti-cheat driver/service files bundled with the game), which was the biggest open risk in the plan. The remaining Phase 0 blockers are just tooling that needs to be installed — nothing about the game install itself looks like a blocker so far.

## How it was confirmed (for reference / repeating the setup)

1. Install Cheat Engine (latest stable; the table was originally tested against 7.2 specifically — noted here in case a future CE update breaks something and this needs revisiting).
2. Launch FM21, load a save.
3. Attach Cheat Engine to `fm.exe`.
4. Open `cheat-table/FM21-Cheat-Table/Source/fm.CT`.
5. Expand `-----[==Features==]-----` (it hides its children by default — look for the small expand arrow to the left of the checkbox) and **tick its checkbox to activate it** — this allocates the pointers the child scripts depend on.
6. Expand and tick **"Current Player"**.
7. In FM21, open any player's profile — CE's "Current Player" fields populate live (confirmed with CA/PA and the full attribute block against Ezri Konsa, Aston Villa).

## Still unconfirmed / open for Phase 1

- **Exact FM21 patch version** — never explicitly confirmed against the table's tested v21.3 baseline, but since pointers resolved correctly this is now low-priority; only worth revisiting if something looks off later.
- **CE version actually used** — worth noting here once known, in case a specific version turns out to matter.

## Exit criterion (from the plan)

> Can attach CE to a running FM21 save and read a known value (e.g. current player's CA) live.

**✅ Met.** Phase 0 is complete — moving to Phase 1 (full-squad read access).
