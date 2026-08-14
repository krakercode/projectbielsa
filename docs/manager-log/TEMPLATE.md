# Manager Session Report Template

For the **AI manager** — whichever model is configured as the active manager per `docs/control-interface.md` — to fill out after a play session. A "session" is a bounded chunk of autonomous management: a single match, a run of fixtures, a transfer window, or however the Phase 4 orchestration loop chooses to checkpoint.

This is distinct from the per-decision JSON logs described in `docs/control-interface.md` ("Logging and replay"), which are machine-oriented — one structured entry per tool-call decision, built for replay and cross-model/cross-profile comparison. This is the higher-level, human-readable counterpart: a reflection written by the manager, in its own words, at the end of a session, for a human reading back through how the team is actually being run.

It should also feed the persistent memory system (`docs/control-interface.md`, "Persistent memory") — after filling this out, the manager should update its memory notes with whatever here is worth carrying into the next session. This report is the reflection; memory is what survives from it.

**Where filled reports live:** `data/manager-log/<save_id>/YYYY-MM-DD-session-N.md` — gitignored, per-save runtime output, not repo documentation (mirrors `data/logs/` and `data/snapshots/`). If a specific report is genuinely worth keeping as a project reference example (e.g. to illustrate the format, or a particularly good/bad piece of reasoning worth discussing), copy it explicitly into `docs/manager-log/examples/` — don't rely on `data/` for anything meant to be reviewed later.

**Write it as the manager, not about the manager.** First person, plain language, the way a manager might actually talk about their own week — not a status report written in the third person about "the AI." The value of this document is in what it reveals about the reasoning and judgment behind the decisions, not in restating what the decision logs already record mechanically.

---

## Session metadata

- **Save / club:**
- **In-game period covered:** (dates, matchweeks)
- **Matches played this session:** (opponent, competition, score)
- **Mode:** cheat / human
- **Manager profile active:** (which config, e.g. `manager_profiles/pragmatic.yaml`)
- **Model:** (which model was driving this session — relevant once multiple adapters are in use)

## What did it do?

Concrete, in order — not a mood summary. Lineups and tactics used (and any changes mid-match), substitutions made and when/why in the moment, transfer activity (bids made, offers received, deals done or fallen through), contract talks, training adjustments, any squad discipline or man-management actions (team talks, individual conversations). Name specific players and matches.

## Did it achieve its goals?

State the goals this session actually started with — board expectations, the manager profile's own stated priorities, match-specific aims (e.g. "keep a clean sheet against a stronger side," "rest key players before a cup tie") — then answer plainly against each: yes / no / partially.

**Report the result before any silver lining.** A 0-3 loss doesn't get reframed as "learned a lot" in the opening line — say the result, then discuss what it means. Don't round a partial success up to a full one.

## Why did it do what it did?

The tactical and strategic reasoning behind the notable calls this session: formation/mentality choices, personnel decisions, substitution timing, which transfer targets were pursued and which passed on and why. Flag specifically anything that departed from the manager profile's stated philosophy (e.g. a normally cautious profile taking a gamble) — those are the calls most worth a human reader double-checking.

## What did it learn?

New, session-specific information about specific players (a hidden quality or weakness now revealed, a form trend, a personality/attitude issue that surfaced), about opponents (a pattern spotted, an exploitable weakness), or about which tactical approach worked or didn't in a specific situation. This is exactly the material that should get written into persistent memory — if it's worth remembering next session, it shouldn't have to be re-discovered from scratch.

## What went wrong?

Poor results, tactical misjudgments, fitness/injury mismanagement, transfer business that backfired, morale or dressing-room damage, anything the manager would clearly do differently in hindsight. **Be honest.** A losing run or a string of bad transfer decisions with nothing acknowledged here is a sign the reflection isn't doing its job, not a sign the session went well.

---

## Carried forward to next session

Concrete items worth remembering going in: promises made to players, plans already in motion (a tactical experiment underway, a youth player being monitored for promotion), transfer targets still being tracked, expected injury return dates, anything the board or a player is expecting a follow-up on.
