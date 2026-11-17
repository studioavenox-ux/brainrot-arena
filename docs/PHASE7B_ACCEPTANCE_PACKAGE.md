# Phase 7B — Roblox Studio acceptance package

Commit under test: `34b6fc5` (Phase 7A) plus this phase's two fixes.
Branch: `arena/0f1a67b1-brainrot-arena`.

**Status: NOT RUN.** Roblox Studio cannot execute in this environment (Linux
container, no Studio, no Rojo, no Roblox control connector). **No row in this
document has been executed in an engine.** Every row is `BLOCKED — no engine`.
The automated gate is recorded separately in §9 and is *not* a substitute.

The purpose of this document is that a developer with Studio can execute it
top to bottom without making a decision, and every row names what to observe,
what to expect, and where the evidence comes from.

---

## 1. What this phase changed

Two real defects were found while preparing the acceptance run. Both were fixed,
with regression tests proven to fail on the old source:

| ID | Defect | Severity | Status |
| --- | --- | --- | --- |
| 7B-D1 | On a **landscape phone** the steal button rendered at `x = -174`, i.e. almost entirely off screen. A phone in landscape could not steal at all. Cause: `StealPanel` is built right-anchored, but the short-landscape branch of `Hud:resize()` positioned it from the left edge without resetting `AnchorPoint`, so the right edge landed at `Space.md` and the panel extended leftwards off screen. | **High** — a core verb is unreachable on a common form factor | **Fixed**, `7B-MOB-1` / `7B-MOB-2` |
| 7B-D2 | The acceptance `ServerStorage` → namespace plumbing (`persistenceOptions()`) had no test. `7A-H` covered `resolveStoreName` alone, so nothing proved the *server* opens the acceptance namespace and never production. | Medium — a test gap on the exact path the acceptance run depends on | **Fixed**, `7B-NS-1..4`, `7B-RESTART` |

One further finding is **not fixed** and is documented as an accepted risk:

| ID | Finding | Disposition |
| --- | --- | --- |
| 7B-R1 | `Main.server` has **no `game:BindToClose`**. `PlayerRemoving` covers a player leaving, but a server *shutdown* (which is what "persistence across server restart" actually exercises) does not guarantee that the final `PlayerRemoving`-queued `SetAsync` completes; Roblox gives ~30 s and `Persistence:save` writes from a `task.spawn`. Progress up to the last round boundary is already durable (the payout saves at the `Results` edge), so the exposure is limited to the current session's tail. | Not fixed in this phase: adding shutdown handling is a durability change of the same class as Phase 7A and deserves its own milestone with its own fail-on-old tests. **Recorded as risk R1; verify in test P-06.** |

---

## 2. Engine availability — the decisive constraint

The server runs **memory-only inside Studio**, regardless of namespace
configuration. From `Persistence.new`:

```lua
self.memoryOnly = (o.memoryOnly == true) or (o.readOnly == true)
    or (RunService:IsStudio() and o.persistInStudio ~= true)
```

and `Main.server` never passes `persistInStudio`. This was verified as a path,
not assumed — the probe below ran the real `Main.server` in each context and
recorded which DataStore namespaces were actually opened:

| Context | `AcceptanceRunId` present | Namespaces opened | `memoryOnly` |
| --- | --- | --- | --- |
| Published server | no | `BrainrotArenaProfiles` | false |
| Published server | yes | **`BrainrotArenaAcceptance_p7b-2026-11-17`** only | false |
| Studio playtest | no | *(none)* | true |
| Studio playtest | yes | *(none)* | true |

**Consequences for this plan:**

- **Studio playtest is valid** for multiplayer, gameplay, touch layout, HUD and
  round flow (§5, §6, §7). Nothing durable is written, so it cannot touch real
  progression — which is also why the "no production writes" rule is easy to
  honour there.
- **Studio playtest is NOT valid** for persistence (§8). Durability can only be
  accepted on a **published private server** with the acceptance namespace.
  Testing persistence in Studio would produce a false PASS ("it reset, but that
  was memory-only") and a false FAIL ("it didn't save").
- This is now enforced by `7B-NS-4`, so if the behaviour ever changes the gate
  fails and this document is wrong in a way the build catches.

---

## 3. Setup

### 3.1 Required Studio settings

| Setting | Value | Why |
| --- | --- | --- |
| File → Experience Settings → Security → **Enable Studio Access to API Services** | **ON** for the persistence place only | Without it every Studio DataStore call raises `403 StudioAccessToApisNotAllowed`. Only relevant if you deliberately override the memory-only default. |
| File → Experience Settings → Security → Allow HTTP Requests | OFF | The game issues no HTTP requests. Leaving it off is the tighter setting. |
| Experience → **Private server** | Required for §8 only | A published private server is the only place durability can be accepted. |
| Studio → View → **Device Emulator** | Used for §7 | |

Roblox reads and writes **the same data stores from Studio as from the live
game**, so "Enable Studio Access to API Services" is exactly why the namespace
guard exists. Enable it on a **dedicated acceptance place**, never on the
production experience.

### 3.2 Required `ServerStorage` configuration (persistence runs only)

Create this in the acceptance place, under **ServerStorage**:

```
ServerStorage
└── BrainrotPersistenceConfig          (Configuration)
    └── AcceptanceRunId                (StringValue)
        Value = "p7b-2026-11-17"       (unique per run — see 3.3)
```

Exact rules, all enforced by `Persistence.resolveStoreName` (it `error()`s at
start-up rather than degrading):

| Configuration | Result |
| --- | --- |
| No `BrainrotPersistenceConfig` at all | Production store. **Correct for the shipped game.** |
| `AcceptanceRunId.Value = "p7b-2026-11-17"` | `BrainrotArenaAcceptance_p7b-2026-11-17` |
| `AcceptanceRunId.Value = ""` | Ignored → production store (not a bare prefix) |
| Child is a `NumberValue` / `BoolValue` | Ignored → production store |
| `AcceptanceRunId` outside the `Configuration` | Ignored → production store |

The last three are deliberate: a malformed config must not silently create a
half-named namespace. They are covered by `7B-NS-3`.

**To force a run against production you would have to pass the production name
with `acceptance = true`, which throws** — there is no client input, no attribute
and no remote that reaches this setting. `7B-NS-2` asserts only one namespace is
ever opened.

### 3.3 Namespace format

```
BrainrotArenaAcceptance_<runId>
```

- Prefix `BrainrotArenaAcceptance_` is mandatory for any non-production store.
- `<runId>` must be non-empty; it raises if empty.
- **Use a new run id for each acceptance session** (e.g. `p7b-2026-11-17-a`).
  This gives a clean slate without deleting anything and keeps runs separable.
- Player keys inside the store are unchanged: `p_<UserId>` (note the sign —
  `p_<userId>` uses the real UserId, so a Studio fake user id of `-1` gives
  `p_-1`). Profile schema is unchanged, so a record written by Phase 6/7A still
  loads.

### 3.4 Private server setup

1. Publish the acceptance place **once** (File → Publish to Roblox As…). Data
   stores do not exist for an unpublished place.
2. Create a **new experience** for acceptance. Never reuse the production
   experience id — a different namespace protects the data, a different
   experience also protects the quota and the settings.
3. Experience Settings → **Permissions / Private servers**: enable
   **private servers** (or use Studio's **Team Test**, which needs no publish and
   is sufficient for §5–§7).
4. Access: **Private**. Do not make the acceptance place public; it has API
   services enabled.

### 3.5 Test accounts

| Requirement | Detail |
| --- | --- |
| Count | **2 accounts minimum** for multiplayer; 3 for the three-player steal matrix |
| Type | Real Roblox accounts, friends with each other, or one owner + invited testers |
| Why real accounts | Studio's local players have fake negative UserIds (`-1`, `-2`) which are **per-session**: P-01 (new profile) will always look new. Restart persistence must be tested with at least one **real** UserId, i.e. a published private server joined by a real account. |
| Progression | Test accounts should be **throwaway**. Even with the namespace guard, a throwaway account means a mistake cannot cost a real player their progress. |

### 3.6 Expected server output

On a healthy start, the Output window shows (verbatim):

```
[Brainrot][server] remotes published
[Brainrot] ACCEPTANCE DataStore namespace: p7b-2026-11-17      <- only when configured
[Brainrot] persistence: store=BrainrotArenaAcceptance_p7b-2026-11-17 acceptance=true memoryOnly=false
[Brainrot][server] persistence ready
[Brainrot] v0.2.0 ready • STANDARD • 48 pickup slots • 180s rounds
```

Record **both** lines every run:

- `store=` must begin `BrainrotArenaAcceptance_`. If it says
  `BrainrotArenaProfiles`, **stop** — the config is not being read.
- `memoryOnly=` must be `false` for §8. `true` means you are in Studio and the
  run cannot test durability.
- `STANDARD` vs `STUDIO QUICK TEST` tells you which timing table applies.

In Studio the same lines appear with `memoryOnly=true`, which is the expected
and safe result.

### 3.7 Which place to open

| Place | Round | Intermission | Results | Use for |
| --- | --- | --- | --- | --- |
| `places/BrainrotArena-QuickTest.rbxlx` | 50 s | 4 s | 5 s | §5, §6, §7 — fast iteration. Chaos at 8 s. |
| `places/BrainrotArena.rbxlx` | 180 s | 12 s | 9 s | §8 timing realism, and the production build |

QuickTest is gated on `RunService:IsStudio()`; a published copy of it would run
standard timings. For §8, publish the **standard** place.

---

## 4. How to record a row

Every test row has six fields. Fill in `Actual`, then set the status. Use
exactly one of `PASS` / `FAIL` / `BLOCKED`.

- **PASS** — observed, matches expected, evidence attached.
- **FAIL** — observed, differs from expected. Attach Output window text and a
  screenshot. File it as a defect; do not adjust the expectation to fit.
- **BLOCKED** — could not be executed (no device, no second account, engine
  unavailable). Never write PASS for a test you did not run.

Evidence format: `screenshot <file>`, `Output: <pasted line>`, or
`video <file>`. A row with no evidence source is not a PASS.

> The rows in this document ship as `BLOCKED — no engine (7B)` because the
> environment cannot run them. That is a truthful status, not a failed test.

---

## 5. Multiplayer acceptance (Studio, 2–3 clients)

**Setup for all of §5:** open `BrainrotArena-QuickTest.rbxlx`, Test tab →
Clients and Servers → **2 players** (3 for M-08), press Play. The server window
is for inspection; do the actions in the client windows.

Let the round auto-start: the intermission is 4 s and both players are routed to
the arena automatically (no portal needed).

| ID | Test | Steps | Expected | Actual | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M-01 | Two clients join | Start with 2 players; observe both client windows and the server window | Two distinct avatars, both on the lobby deck during Intermission; server Output lists both players; no errors | — | **BLOCKED — no engine (7B)** | |
| M-02 | Spawning / arena routing | Wait for Intermission → Playing | Both players are moved to **different** arena pads at the deadline with no input; nobody is left in the lobby; no `[Brainrot] route fallback` lines in a normal session | — | **BLOCKED — no engine (7B)** | |
| M-03 | Arena interaction (movement + collision) | Walk, jump, fall off an island, reset the character mid-round | Movement feels responsive at WalkSpeed 22; falling returns you to the arena with your score kept; a dead avatar is never force-teleported | — | **BLOCKED — no engine (7B)** | |
| M-04 | Catching a specimen | Walk into a glowing cell; watch the cell counter (top-left) and the leaderboard | Cell disappears, counter increments by 1 (Common), 5 (Rare) or 10 (Prismatic); a toast names the catch; the other client sees the cell vanish | — | **BLOCKED — no engine (7B)** | |
| M-05 | Stealing | Player A comes within ~13 studs of B who is **carrying** cells; A presses **E** (or taps STEAL) | Exactly ONE carried cell moves A←B; both HUDs update; the steal button shows an 8 s cooldown; B gets 4 s immunity and cannot be re-tagged by A for 12 s | — | **BLOCKED — no engine (7B)** | |
| M-06 | Steal is refused when out of range | A stays ~40 studs from B, presses **E** | Refused with a message; **no cooldown starts** (the button must not go on cooldown for a refused steal); B's cells unchanged | — | **BLOCKED — no engine (7B)** | |
| M-07 | Round completion and payout | Play one full round; at the deadline observe the results card | Both clients return to the lobby; the results card lists both scores; winner is the top score; card auto-closes after 5 s | — | **BLOCKED — no engine (7B)** | |
| M-08 | Correct payouts (the exact arithmetic) | Note each player's score `S` in the results card, and the coins before/after | `coins gained = 10 (participation) + 2 × S + 30 (winner bonus if top score)`. Worked example: winner with 7 cells → `10 + 14 + 30 = 54`; loser with 3 cells → `10 + 6 = 16`. Verify the coin chip matches exactly. | — | **BLOCKED — no engine (7B)** | |
| M-09 | Multiple consecutive rounds | Let 3 rounds run without touching anything | Round counter increments 1→2→3; coins accumulate (no reset between rounds); stage labels run COLLECT → COMPETE → CHAOS → FINAL RUSH each round; exactly ONE chaos event per round | — | **BLOCKED — no engine (7B)** | |
| M-10 | Late join mid-round | Join a third client while Playing | The late player is routed into the arena on the next heartbeat, appears on both leaderboards with 0 cells, and can catch and steal immediately | — | **BLOCKED — no engine (7B)** | |
| M-11 | Client cannot score itself | Advanced, optional: in a client console (F9) attempt to change a coin value or fire a `BrainrotRemotes.Request` with a bogus verb | No effect: coins are server-owned, the verb whitelist rejects unknown actions, and extra arguments are rejected | — | **BLOCKED — no engine (7B)** | |

---

## 6. Persistence acceptance (published private server)

**Setup for all of §6:** published **standard** place, private server,
`BrainrotPersistenceConfig` present (§3.2), signed in as a real account. Confirm
the two start-up lines in §3.6 **before** the first row, and record them.

All §6 rows run against the acceptance namespace only. Production is never
opened — `7B-NS-2` asserts this for the code path, and P-00 confirms it for the
actual session.

| ID | Test | Steps | Expected | Actual | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| P-00 | Namespace isolation | Read the start-up lines | `store=BrainrotArenaAcceptance_<runId>`, `acceptance=true`, `memoryOnly=false`. Anything else is a **FAIL** — do not proceed. | — | **BLOCKED — no engine (7B)** | |
| P-01 | New profile creation | Join with an account that has **never** played in this namespace | `GetAsync` returns nil → a default profile is created and is writable (Coins 0, Rounds 0, empty specimen log). No error in Output. | — | **BLOCKED — no engine (7B)** | |
| P-02 | Coin saving | Catch cells, finish the round, note the coin total, then leave and rejoin | The same coin total is present after rejoining. | — | **BLOCKED — no engine (7B)** | |
| P-03 | Specimen saving | Catch at least 3 different species, leave, rejoin, open the specimen log (**C** or the gear button) | The species and their counts are still there, and counts are cumulative across rounds. | — | **BLOCKED — no engine (7B)** | |
| P-04 | Statistics saving | Play 2 rounds, note Rounds / Wins / BestScore, leave, rejoin | Rounds, Wins and BestScore match exactly; BestScore is the best single round, not the sum. | — | **BLOCKED — no engine (7B)** | |
| P-05 | Leave and reconnect (direct via Join) | Leave deliberately; rejoin within a minute | Progress present. Note in evidence whether the server had already shut down or not — that is what separates P-05 from P-06. | — | **BLOCKED — no engine (7B)** | |
| P-06 | Persistence across server restart | Finish a round (so the payout is written), then **stop the server** (or let it empty), then start a fresh server and rejoin | Progress up to the last completed round is present on the fresh server. **Expected risk:** progress earned *after* the last `Results` edge but before shutdown may be lost — this is risk **R1** (§1). Record exactly how much was lost, if any. | — | **BLOCKED — no engine (7B)** | |
| P-07 | Failed load refuses to overwrite | Simulate an unreadable store, then attempt to earn and leave. Suggestion: temporarily make `BrainrotPersistenceConfig.AcceptanceRunId` a name whose store is broken/unavailable, or run a build with `storeFail`. Observe Output. | The session logs `left with an unsaved session (profile Failed)`, **nothing is written**, and the pre-existing record is byte-identical afterwards. This is the Phase 7A guarantee seen in a real engine, and it is the single most important row in this section. | — | **BLOCKED — no engine (7B)** | |
| P-08 | Halo purchase persists | Buy a halo (100 coins) with **B**, leave, rejoin | The halo is still owned and equipped; the coin balance dropped by exactly 100. | — | **BLOCKED — no engine (7B)** | |
| P-09 | Production untouched (audit) | After the whole run, inspect the **production** experience's data (or its stats), and confirm the acceptance place was never configured to it | No acceptance-run writes in production. The guard in §3.2 plus P-00 is the evidence; this row is the human audit of that claim. | — | **BLOCKED — no engine (7B)** | |

---

## 7. Mobile acceptance (Studio Device Emulator, then a real device)

**Setup:** QuickTest place, 1 client (2 for the steal feel test). Studio → View →
**Device Emulator** → choose a phone preset: iPhone 14 (390×844), Pixel 7
(412×915), or a landscape preset (844×390). Rotate via the Device Emulator's
orientation control.

Layout is responsive with these breakpoints, which is why the rows name them:
`compact = width < 780`, `short = height < 520`, `narrow = compact and width < 380`.

| ID | Test | Steps | Expected | Actual | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| T-01 | Touch movement | Use the thumbstick to walk, tap JUMP, drag the camera | The thumbstick and jump respond; the camera can be dragged without fighting the thumbstick; no HUD element sits under the thumbstick or jump button | — | **BLOCKED — no engine (7B)** | |
| T-02 | Catch via touch | Walk into a cell (catching is proximity-based, not a tap) | Catching works by walking; there is no button to press, and the counter + toast confirm it | — | **BLOCKED — no engine (7B)** | |
| T-03 | **Steal button reachable — portrait** | 390×844 portrait: locate STEAL (bottom-right) and tap it | Fully on screen, ≥ 44 px tall, tappable with a thumb. *This is the row that 7B-D1 broke in landscape.* | — | **BLOCKED — no engine (7B)** | |
| T-04 | **Steal button reachable — landscape** | Rotate to 844×390: relocate STEAL | **Round 7B-D1:** the steal button moved to the **bottom-left** and is fully on screen. Before the fix it rendered at x = -174, i.e. only 12 px were tappable. Verify it is tappable and does not sit under the thumbstick. | — | **BLOCKED — no engine (7B)** | |
| T-05 | Ability button | Tap the ABILITY button beside STEAL | Fires the ability; the button shows its cooldown sweep; it is fully on screen in both orientations | — | **BLOCKED — no engine (7B)** | |
| T-06 | HUD positioning / safe area | Portrait and landscape: check the coin chip, cell counter, clock, specimen chip, RANKS, HELP | Nothing is clipped by the notch or the device edge (`ScreenInsets.CoreUISafeInsets` is used); nothing overlaps another control; the brand wordmark is hidden on phones by design | — | **BLOCKED — no engine (7B)** | |
| T-07 | Screen scaling — small phone | 320×568 (iPhone SE 1st gen class); also 360×740 | Nothing clipped or overlapping; at 320 the two end chips use their narrow sizes; text remains legible (no truncation of the clock digits) | — | **BLOCKED — no engine (7B)** | |
| T-08 | Screen scaling — tablet | iPad preset (e.g. 820×1180) | Layout uses the desktop arrangement; brand cluster visible; bottom bar hugs the bottom edge (no phone lift) | — | **BLOCKED — no engine (7B)** | |
| T-09 | Responsive interaction (rotation) | Rotate portrait → landscape → portrait mid-round | Every control returns fully on screen; nothing is stranded off screen; the round is not interrupted | — | **BLOCKED — no engine (7B)** | |
| T-10 | Touch targets in the action bar | Tap SHOP, INV (specimen log), SETTINGS, RANKS, HELP | Each opens its panel on the first tap; all are ≥ 44 px tall; `Shop/Inventory/Settings` are above the thumbstick zone | — | **BLOCKED — no engine (7B)** | |
| T-11 | Real device | Repeat T-01, T-04, T-06, T-09 on a physical phone via the Roblox app on the private server | Matches the emulator; thumb reach is comfortable; no accidental jumps when tapping the bottom bar | — | **BLOCKED — no device** | |

> **Known cosmetic risk (not fixed):** on phone widths the three-button action
> bar (`Shop / Inventory / Settings`, 252 px wide, centred) geometrically
> overlaps the steal and ability buttons, because all sit at `barLift` 118 px.
> The bar is at `ZIndex` 4 and its buttons at 3, so the steal label and cooldown
> sweep are **visible and tappable** only on the right-hand portion; the overlap
> is partly transparent framing. On landscape phones the ability panel overlaps
> the bar's left edge. This is recorded as risk **R2**; T-03/T-04/T-10 must
> confirm the actual tap behaviour, and if any tap is lost it is a **FAIL** that
> promotes R2 to a defect.

---

## 8. Automated results (not a substitute)

Gate at the commit under test, `python3 tools/check.py`:

```
PASS Studio place exports built
PASS All 32 Luau files compile
PASS Strict type analysis: authority modules + configuration
PASS Core rules and 100 simulated 12-player rounds
PASS Production adapters against mocked Roblox services
PASS Place structure, loadable API properties and geometry
PASS Art direction: palette, hierarchy, legibility, lighting rig
PASS Deterministic export rebuild
PASS Git diff whitespace check

345 tests passed; 0 failed
```

Breakdown: core 150, adapters 124, export 36, art 35. Baseline entering Phase 7B:
338 (core 150, adapters 117, export 36, art 35). +7 tests, +0 failures.

New in Phase 7B: `7B-NS-1..4`, `7B-RESTART`, `7B-MOB-1`, `7B-MOB-2`. Both
mobile tests were run against the pre-fix HUD and fail with
`steal button off screen at 844x354 -> -174,286 186x52`, then pass after the fix.

**These are contract tests against service doubles.** They exercise real
production source through a mocked Roblox boundary (no engine physics, no
renderer, no replication, no audio, no real DataStore). They cannot and do not
prove any row in §5–§7.

---

## 9. Execution order (do this, in this order)

1. **Setup (§3).** Publish the acceptance place, set the config, confirm §3.6.
   If the start-up line does not say the acceptance namespace, stop.
2. **§7 mobile, portrait + landscape** — fastest to run, and T-04 is the
   regression for a fix made in this phase, so it is the most informative row.
3. **§5 multiplayer** — one full round with 2 clients, then M-09's three rounds.
4. **§6 persistence** — private server, real accounts. Do P-00 first and P-07
   (the most important row) before the convenience rows.
5. **Record every row**, then update §3/§5 of the Phase 7B report with the status.

Nothing in this plan should be executed against the production experience or a
production namespace.
