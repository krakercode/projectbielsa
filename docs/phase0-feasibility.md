# Phase 0 — Environment & Feasibility Check

Status as of 2026-08-14, checked on the machine at `C:\Users\User\Desktop`.

## Findings

| Requirement | Status | Notes |
|---|---|---|
| Football Manager 2021 | ✅ Installed | Steam app id `1263850`, installed at `D:\SteamLibrary\steamapps\common\Football Manager 2021`. `fm.exe` present. Build id `6682909` per Steam manifest (`appmanifest_1263850.acf`). No `EasyAntiCheat`/`BattlEye` binaries found in the install directory — good sign for Cheat Engine attach, but unconfirmed until actually tested against a running process. |
| FM21 patch version (21.4.0 expected) | ⚠️ Unconfirmed | Couldn't determine the in-game version string from the install directory alone. Steam shows this install as fully up to date (no pending update), so it's very likely 21.4.0 (the final patch SI shipped), but this should be confirmed from the in-game "About" / main menu screen. |
| Steam | ✅ Installed | Multiple library folders in use (`C:\Program Files (x86)\Steam`, `C:\Games\new steam`, `C:\Steam`, `D:\SteamLibrary`). FM21 lives in the `D:\SteamLibrary` one. |
| Cheat Engine | ❌ Not installed | No Cheat Engine install found anywhere on the `C:` or `D:` drives. Install the latest stable release; only fall back to 7.2 specifically if the table won't attach/resolve on it (see note below). |
| FM21-Cheat-Table (xAranaktu/FM21-Cheat-Table) | ✅ Downloaded | Cloned into `cheat-table/FM21-Cheat-Table/` (`fm.CT` + `changelog.txt`). Its README states it was **tested with Cheat Engine 7.2 on Win10 x64, Steam game version v21.3** — one version behind the v21.4.0 the plan assumed. Worth checking whether pointers still resolve on our v21.4.0-ish build once attach is tested. |
| Anti-tamper / attach test | ⏸ Not yet run | Needs Cheat Engine installed and FM21 running with a save loaded — see manual steps below. |

## What this means

The good news: FM21 itself is already installed and looks clean (no visible anti-cheat driver/service files bundled with the game), which was the biggest open risk in the plan. The remaining Phase 0 blockers are just tooling that needs to be installed — nothing about the game install itself looks like a blocker so far.

## Manual steps needed (can't be done by the agent)

These involve downloading and running third-party executables / attaching a debugger to a running game process, which needs to happen on your end:

1. **Install Cheat Engine** — latest stable release from the official site (cheatengine.org) or GitHub releases. Watch out for the bundled third-party offers in the official installer — decline all of them, or use the portable/zip build if available. If the table (step 3 below) fails to attach or its pointers don't resolve, uninstall and try CE 7.2 specifically instead — that's the version the table was actually tested against.
2. **Confirm the FM21 patch version** in-game (main menu → should show a version string, or check Steam → Football Manager 2021 → Properties → Installed Files). Report back what it says — the table was tested on v21.3, and we want to know how far our build has drifted from that.
3. **Launch FM21, load or start a save**, then open Cheat Engine and attach to the `fm.exe` process.
4. **Open `cheat-table/FM21-Cheat-Table/Source/fm.CT`** in Cheat Engine while attached, and try reading a known value (e.g. the current player's CA) as the table's README describes. This is the actual exit criterion for Phase 0 — confirms both that CE can attach at all, and that the table's pointers still resolve on this build.

Once step 4 works (or fails with a specific error), report back what happened and we'll move to Phase 1 (or troubleshoot the attach if it's blocked).

## Exit criterion (from the plan)

> Can attach CE to a running FM21 save and read a known value (e.g. current player's CA) live.

Not yet met — pending the manual steps above.
