# Alternative targets — is an older, simpler football management game a better testbed?

**Status:** research and decision document. Written 2026-08-23. **Nothing in here
has been verified against a running CM binary** — see "Open questions" for what is
asserted from community sources versus what is actually unknown.

**Decision reached:** FM21 remains the experimental target of record. CM 01/02 is
worth evaluating as a *pilot harness* — a fast, cheap place to build and debug the
loop and shake out the experimental design. A time-boxed spike decides whether that
is real. See [`../cm0102/docs/spike.md`](../cm0102/docs/spike.md) for the spike, and
[`../cm0102/README.md`](../cm0102/README.md) for how CM work stays separated from FM
work.

---

## 1. "Decompile" is the wrong word for the right idea

The question that prompted this was whether it would be easier to *decompile* an
earlier, simpler game. It is worth separating two very different things, because
one is a multi-year project and the other is a weekend:

- **Full decompilation** — recovering recompilable source from a ~6 MB MSVC C++
  binary, matching-build style. Even for well-loved decomp targets this is
  person-years of work, and CM 01/02 is heavy on STL and compiler-generated code.
  **This project should not attempt this.**
- **Targeted reverse engineering** — identifying the handful of structures and
  entry points actually needed: the player/club record layout, the squad list, the
  in-game date, and the "advance a day" path. This is tractable, and for CM 01/02
  a large fraction of it *already exists in the open*.

Everything below is about the second. If a future session finds itself planning a
decompilation, it has misread this document.

---

## 2. What prompted the question

Eight sessions in, the loop works: `scripts/manager/run_decision.js` reads the live
game, asks a model for an XI, applies it through the UI, verifies it, and logs the
decision — PLAN.md's Phase 4 exit criterion, met and verified twice
(`docs/session-log/2026-08-16-closing-the-loop.md`).

Two things are stuck, and both are in `TODO.md`:

1. **The agent cannot advance the game.** It can pick a team but not play. The
   in-game date is not readable from memory at all. The 2026-08-16 log names this
   "the real frontier."
2. **Throughput.** A decision costs ~86 s; matches run in real time; every read
   re-scans 2.4 GB because heap addresses move on every launch. PLAN.md's own
   "Variance and cost" section names cost per run as *the* practical limiter and
   sizes the 2×2 grid at roughly 120 runs.

An older game is a plausible answer to both. It is a bad answer to some other
things, which is what makes this a trade-off rather than an obvious win.

---

## 3. What the FM21 work is actually worth on a switch

The important question is not "is CM easier" but "how much of eight sessions
survives". Concretely:

### Dead on a switch — every offset, signature and locator

`cheat-table/`, `scripts/lua/`, `scripts/win/scan_mem.ps1`,
`scripts/manager/read_squad.js`, `locate_lineup.js`, `set_lineup.js`,
`read_lineup.js`, `data/roster/`.

This is real loss, and it includes the field-by-field verification against FM's own
UI that is the entire basis for trusting the current reads.

### Fully portable — the intellectual core

PLAN.md's "Experimental Design & Validity" section (the 2×2, matched seeds and
regens, the masking argument, baselines, process metrics, the deliberately-late leak
audit) is target-agnostic. So is `docs/control-interface.md`. None of this cares
which game is underneath.

### Portable behind an interface — the decision layer

`scripts/manager/pick_lineup.js`, `prompts.js`, `tactic.js`, `run_decision.js`,
`provider.js`, `profiles/`, plus validation, self-correction and decision logging.

These are already close to target-agnostic by construction. `squad_state.js`
consumes a JSON dump and emits a compact, scale-converted, mode-filtered squad;
`pick_lineup.js` fills the active tactic's *slots*. Only two things are FM-specific:
the state producer (`read_squad.js`) and the action executor (`set_lineup.js` plus
the PowerShell input layer). `run_decision.js` currently hardcodes both, along with
`powershell.exe` and a Tactics-sidebar click coordinate.

**Conclusion:** the cost of a switch is "rebuild the read/write layer" — roughly 2–3
sessions of the ~8 done — not "start over". That is the single most useful number in
this document.

---

## 4. The case for CM 01/02

Mapped onto the two blockers above, not as a general list of virtues.

**Advancing the game becomes cheap.** One "Continue"; a 2001 simulation processes
near-instantly on modern hardware. The blocker named as the real frontier largely
evaporates, and with it the thing that stops any scenario from running.

**Static addresses exist.** The community standardises on a single build, **3.9.68**,
and forum offset threads cite fixed exe-relative data addresses (e.g. `00AE23BC`).
Compare FM21: a pointer scan produced 27 candidate static paths and **none survived
a restart** (`docs/session-log/2026-08-15-pointer-validation.md`). This project has
lost multiple sessions to moving heaps, stale render generations, and — memorably —
a buffer freed and reused to hold *Leicester's* squad between a drag and its
verification read.

**State can come off disk.** The save format is well understood by the community
(mature editor ecosystem; saves can be written uncompressed). PLAN.md requires
**save snapshots at every decision point** for cross-model replay — trivial with a
legible on-disk save, awkward with FM21.

**Open reverse-engineering material.** [`nckstwrt/CM0102Patcher`][patcher]
(open-source C#), `CM0102Loader`, CMRTE, and 20+ years of forum offset threads —
against FM21's single community cheat table. Usefully, the binary's assertion
strings carry original source filenames and line numbers (`player_stats.cpp 3828`
appears in a community bug report), which materially helps any RE work.

**Throughput and parallelism.** The game is freely distributed, has no anti-tamper,
and runs under Wine on Linux (documented down to Raspberry Pi). That means N
instances under Xvfb on one box. This is plausibly the difference between the ~120-run
grid being affordable and not — an argument PLAN.md already makes against itself.

**A simpler write layer.** Fixed low resolution, no animation, static layout, so
coordinate clicking is far more reliable than FM21's drag-and-drop — where the swap
dropdown's candidate order turned out not to be stable, forcing row-drag as the only
usable primitive.

---

## 5. The case against

Stated as honestly as the case for, because the strongest objection is not an
engineering one.

**The research claim weakens — this is the real argument.** PLAN.md's premise is
measuring whether LLMs can learn and play a *complex* game under human-equivalent
constraints. CM 01/02 is much shallower: no press conferences, thin tactical
vocabulary, little player interaction, far fewer decision surfaces. "An LLM managed
CM 01/02" is a weaker finding than "an LLM managed FM21", and no amount of
engineering convenience fixes that. **This is why the recommendation below is not a
switch.**

**Training-data contamination is worse, not better.** CM 01/02's match-engine
exploits are famous and thoroughly documented online — the Creativity bug (the
engine using Reflexes where it should use Creativity), the notorious formation
exploits, the wonderkid lists. PLAN.md's "You cannot instruct a model to forget"
section already flags this hazard; an ancient, heavily-written-about game maximises
it. A strong result could turn out to be "the model recalled the exploit", which is
not the thing being measured. FM21 has the same problem at lower intensity.

**Human mode may be less faithful.** PLAN.md Phase 5 wants to read FM's own
"known-to-user" flags so human mode is *authoritative* rather than reimplemented.
Whether CM 01/02 has an equivalent knowledge model is **unverified**. The existence
of a community "hide all stats" patch suggests attribute visibility is at least
controllable, but that is not the same as a per-player scouting knowledge model, and
a coarser one would degrade the experiment's central condition.

**Verified work is discarded.** Not just code — the *confidence*. The current FM21
reads are trusted because 752 immutable fields were checked transitively against
FM's own UI. A CM read layer starts at zero on that.

---

## 6. Recommendation

**Do not switch the experimental target.** Keep FM21 as the target of record;
PLAN.md's phases stand unchanged.

**Do evaluate CM 01/02 as a pilot harness** — a place to build and debug the
orchestration loop, exercise the untested agentic `tools` strategy, and *measure
cost per season* cheaply, before spending FM21 wall-clock on it. The things this
project keeps getting bitten by (untested code paths, unrun strategies, unmeasured
costs) are exactly the things a fast harness surfaces.

Honest cost of the dual-target posture: it requires a target-agnostic state/action
interface that does not exist yet, and two targets to maintain. The interface is
worth extracting regardless — `run_decision.js` currently hardcodes `powershell.exe`
and a click coordinate, which is a design smell independent of any pivot.

**Decide on evidence, not on this document.** The spike in
[`../cm0102/docs/spike.md`](../cm0102/docs/spike.md) is time-boxed to one session
with four exit criteria, mirroring how FM21's Phase 0 was run. CM 01/02 first
because the RE material is best there; CM 03/04 as the fallback if game depth turns
out to be the binding constraint (it is a meaningfully deeper game, still ancient
and fast, with an active patching community — but far less open RE material).

**Containment rule:** all CM work lives under `cm0102/`. Nothing under `scripts/`,
`cheat-table/` or `data/` changes. The decision stays reversible by deleting one
directory.

---

## 7. Open questions — unverified, do not treat as settled

1. **Does CM 01/02 have a per-player scouting knowledge model** that human mode
   could read authoritatively, as PLAN.md Phase 5 wants from FM? Unknown. Decides
   whether CM can host the real experimental condition or only the pilot.
2. **How fast does a season actually process**, wall-clock, with a full database
   loaded? Asserted as "fast" from the game's age; never measured.
3. **Does it run headless under Wine + Xvfb, and can N instances run in parallel**
   against separate save directories? Plausible, unconfirmed — and it carries the
   whole parallelism argument.
4. **How much open RE material does CM 03/04 really have?** Searching found an
   active patching community but nothing like CM 01/02's offset archive.
5. **Is the in-game date reachable statically**, or does it need the same scanning
   the FM21 project has been fighting? This is criterion A of the spike.

---

## Sources

- [nckstwrt/CM0102Patcher — open-source CM 01/02 patcher (C#)][patcher]
- [champman0102.net — "Offsets" thread](https://champman0102.net/viewtopic.php?t=1540)
- [champman0102.net — patching tutorial (CM0102Patcher, Tapani, Saturn, OllyDbg)](https://champman0102.net/viewtopic.php?t=2956)
- [champman0102.net — CMRTE real-time editor](https://champman0102.net/viewtopic.php?t=2986)
- [champman0102.net — `player_stats.cpp 3828` assertion report](https://champman0102.net/viewtopic.php?t=3505)
- [Everyday Linux User — running CM 01/02 under Wine](https://www.everydaylinuxuser.com/2012/02/how-to-get-championship-manager-0102.html)
- [Raspberry Pi forums — CM 01/02 on ARM via Wine](https://forums.raspberrypi.com/viewtopic.php?t=377867)
- [JonBetts/CM0102-Starter-Kit](https://github.com/JonBetts/CM0102-Starter-Kit)

[patcher]: https://github.com/nckstwrt/CM0102Patcher
