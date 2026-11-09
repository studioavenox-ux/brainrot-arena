# Phase 5 — Steal, Stages and Survival Events

Spec v1.0, "COLLECT. STEAL. SURVIVE. DOMINATE." This phase turns the collecting
prototype into the full three-minute round: a staged timeline, a real stealing
verb, five survival events with warnings, and durable progression.

Everything below is implemented in the repository and covered by the automated
gate. **Roblox Studio was not available in this environment**, so the Studio
acceptance matrix in `docs/TEST_REPORT_PHASE5.md` is marked *pending*, not passed.

---

## 1. What changed, in one screen

| Area | Before (Phase 4) | Now (Phase 5) |
| --- | --- | --- |
| Round structure | Playing → Results | Playing split into **Collect → Compete → Chaos → Final Rush**, each boundary banks what you carry |
| Inventory | one score number | **carried** (stealable) vs **banked** (safe); `score` is always their sum |
| Offence | none | **STEAL**: short-range tag that moves one carried cell, 8 s cooldown, server-validated |
| Events | low gravity only | five kinds: low gravity, slippery stone, moving rafts, collectible rush, vanishing paths — all warned 6 s ahead |
| UI | score, coins, clock, board | plus stage chip, event banner (warning + live), steal button with live cooldown, carried/banked readout, steal stats on the results card |
| Persistence | session only | DataStore profile: coins, specimen log, lifetime stats, halo — schema-checked, retried, memory fallback |
| Map | 824 static parts | 906 (82 new event parts), same walkable geometry |

---

## 2. The round (spec §4)

Production timeline, elapsed seconds from the start of `Playing`:

| Stage | Starts | What it means | How the player knows |
| --- | --- | --- | --- |
| Collect | 0 s | nothing carried can be stolen yet | clock header reads `COLLECT` |
| Compete | 45 s | carried cells are at risk | header switches, toast on bank |
| Chaos | 105 s | the wildcard window lands here | header reads `CHAOS` in violet |
| Final | 150 s | last bank, fastest respawns | header reads `FINAL` in danger red |
| Results | 180 s | winners, coins, rewards | results card |

* Every boundary is server-driven (`RoundMachine:step`), never a client timer.
* Each boundary **banks** every player's carried cells. That is what makes
  "empty-handed at the bell" impossible: you can lose the carried stack, never
  the banked score.
* `Timing.Round` is still exactly **180 s**, asserted by the core suite.
* Quick-test rounds stay 30 s; the machine drops stage boundaries that fall past
  the deadline instead of trimming them, and falls back to the legacy single
  event window if the event plan does not fit.

## 3. Stealing (spec §3B, §9)

The verb is `Steal`. It carries **no arguments** — no target, no distance, no
value. The server:

1. rate-limits the request per player (`record.requests.StealSent`, 8 s);
2. finds the nearest *participating* player within `Config.Steal.Range` (13 studs)
   from the server's own `HumanoidRootPart` positions;
3. asks `RoundMachine:trySteal` to decide.

`trySteal` refuses, in order: a non-live round, malformed ids, self-targeting,
unknown/non-participating players, out-of-range, thief on cooldown, thief or victim
under spawn protection, victim still immune from a previous steal, the same pair
inside the 12 s repeat window, and an empty carried pile. Only then does it move
the victim's **largest carried cell** to the thief.

Fairness properties the tests pin down:

* the victim's banked score is never touched (stealing an empty pile returns
  `empty` and moves nothing);
* the stolen cell lands in the thief's *carried* pile, so it can be taken back;
* a victim gets 4 s of immunity, a spawning player 3 s of protection;
* spending is server-side only (`Persistence.buyHalo` takes a server constant,
  never a client price).

## 4. Survival events (spec §3C)

| Kind | What the player feels | Implementation |
| --- | --- | --- |
| `LowGravity` | floaty jumps | `Workspace.Gravity` 196.2 → 62, plus a prismatic beacon pulse |
| `Slippery` | ice | `CustomPhysicalProperties` friction 0.7 → 0.06 on arena surfaces |
| `MovingPlatforms` | three rafts circle the court | baked `EventRaft_*` parts moved by CFrame on a 30 s orbit |
| `CollectibleRush` | cells come back fast | `PickupLedger.respawn` 5 s → 1.5 s |
| `VanishingPaths` | four spans rise, then blink out | baked `EventPath_*` parts toggle collide/transparency |

* **Warnings:** every window is announced 6 s ahead (`Timing.Warning`) with the
  event's own label; the HUD shows `INCOMING: <NAME> • 4` then `NAME • ACTIVE 18`.
* **Predictable timing:** the schedule is built from `Config.Events` at the start
  of the round and rotated by round id, so every client and every replay of a
  round agree (`RoundMachine:buildSchedule(roundId)`).
* **Nothing is left running:** `EventDirector:stop()` — called on every event close
  *and* on every phase change — restores gravity, friction, path solidity and the
  rafts' parked pose. A dropped effect cannot leave the arena broken.

## 5. Map additions (spec §5)

`tools/events.py` bakes the event geometry into the same world model as everything
else, so the export path, the previews and the runtime all see it:

* three rafts `EventRaft_{A,B,C}` on a 25.5-stud orbit in the clean lane between the
  r = 20 and r = 43 pickup rings, top surface 21.9 (0.9 studs up: a step, not a
  climb), teal stone with a warm underglow lip and four dark studs;
* twelve dashed orbit inlays per raft, so the circuit reads before the event runs;
* four vanishing spans `EventPath_{0..3}` at 45°/135°/225°/315°, starting at
  r = 49 outside the rail and reaching out over open water;
* four anchor markers that stay visible at rest to explain where the spans appear.

Every event part is **non-colliding at rest**, so a parked raft can never trap a
player and a hidden span can never be walked on. `artcheck` and `verify_place`
both assert that.

Part budget: **906** static parts (was 824). The extra 82 are event geometry. The
per-visible-cell cap (20), the all-cells ceiling (960) and the seven-light rule are
unchanged — those are the limits that actually describe a low-end phone.

## 6. UI (spec §6)

New/changed in `Hud.luau`, `Panels.luau`, `Theme.luau` (generated from `tools/ui.py`):

* **Steal panel** (bottom right, `Panels.stealPanel`): hook glyph, state label,
  cooldown veil that drains left-to-right, and a carried/banked readout above it.
  States: `STEAL READY` / `3.2s` + `RECHARGING` / `PROTECTED 2s` / `STEAL` +
  `COLLECT PHASE` when the round is not live. Keyboard alias: **E**.
* **Stage chip** (desktop, under the cell counter): the full stage sentence, e.g.
  `CHAOS — EVENTS ARE LIVE`. Phones drop the chip and use the clock header instead
  (see below) to keep small screens uncrowded.
* **Clock header** names the stage during a live round (`COLLECT`, `COMPETE`,
  `CHAOS`, `FINAL`) and the phase otherwise.
* **Event banner** shows `INCOMING: LOW GRAVITY • 4` (amber) then
  `LOW GRAVITY • ACTIVE 18` (cyan), straight from the server schedule.
* **Results card** now also reports `STEALS` and `LOST`.
* **Help card** explains banking and stealing, and lists the events.

Every control is wired to a real handler and every value is bound to server state;
`Kit.button` asserts a handler exists, so a decorative button cannot be built.

### Responsive fixes found while rendering the plates

* phones: the brand cluster (wordmark *and* tagline) is hidden — a stray tagline was
  showing through behind the coin panel;
* phones: the clock is now centred on the screen (`width − 300`, was `− 368`) so it
  no longer hides behind the coin panel;
* phones: the specimen chip reads `SPECS 0/6` so it stops clipping at 112 px;
* phones: the RANKS chip no longer overlaps the specimen chip, and hides itself
  while the leaderboard is open;
* desktop: the help chip moved to y = 172 to make room for the stage chip.

## 7. Progression and data (spec §8)

`src/server/Persistence.luau`:

* one profile per player: `Coins`, `Halo`, `Specimens`, `Rounds`, `Wins`,
  `BestScore`, `TotalScore`, `Steals`, `Lost`, `Picked`, `Version`;
* `sanitise()` is the only constructor: wrong types become defaults, negative or
  non-finite numbers are clamped, unknown species keys are dropped, wins can never
  exceed rounds;
* `applyRound()` is the only place a round pays coins or increments stats, and it
  takes the machine's own result;
* reads are pcall-protected with three retries and merge rather than replace, so a
  slow load cannot erase what the session already earned;
* writes are pcall-protected with three retries; a failure is logged and counted,
  never raised into a gameplay loop;
* without a DataStore the server runs in memory and says so once in the log.

The round score itself is **never** persisted; it is created and destroyed by the
round, exactly as the spec requires.

## 8. What the automated gate covers

`python3 tools/check.py` → **248 tests, 0 failures**:

* 107 core Luau assertions (was 90): the 90 existing plus steal outcomes, cooldown,
  spawn protection, victim immunity, repeat-window refusal, empty-pile refusal,
  banked-score safety, stage banking, schedule warnings, event lifecycle;
* 70 adapter assertions (was 60): the 60 existing plus a real client `Steal` request
  through the mock engine, an out-of-range refusal, an argument-forgery refusal,
  and eight persistence tests (defaults, corruption repair, halo pricing, save /
  reload, forced DataStore failure);
* place, art, determinism and whitespace checks, unchanged in spirit, updated for
  the new part count and the new event geometry.

See `docs/TEST_REPORT_PHASE5.md` for the split between automated checks and the
Studio matrix, and `docs/KNOWN_LIMITATIONS.md` for what is deliberately not done.
