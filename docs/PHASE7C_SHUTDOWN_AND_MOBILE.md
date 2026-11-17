# Phase 7C — Shutdown Safety and Mobile UI Completion

Continues Phase 7B from commit `8712d78` (345 automated tests).
Branch: `arena/0f1a67b1-brainrot-arena`.

**This document reports automated and mock-based verification only.** No Roblox
Studio session, published server, real DataStore or real device was available in
this environment (Linux container, no Studio, no Rojo). Nothing below is an
engine result. §5 separates the three kinds of evidence explicitly.

---

## 1. Outcome

| Task | Status | Evidence |
| --- | --- | --- |
| 1 — Graceful shutdown persistence | **Implemented** | 10 new adapter tests; 5 fail on the previous source |
| 2 — Mobile ActionBar overlap | **Fixed** | 6 new geometry tests; 4 fail on the previous source |
| 3 — Full gate | **Green** | 361 passed, 0 failed (was 345) |
| 4 — Documentation | This file + package/TESTING updates | |
| 5 — Completion criteria | **Not release-ready** — see §6 | |

Two defects were found that were **not** in the task brief, and one of them was
losing player data:

| ID | Defect | Severity | Status |
| --- | --- | --- | --- |
| **7C-D1** | `PlayerRemoving` **queued** its final save and then immediately called `release()`, which bumps the session generation. The queued write then saw a newer generation and aborted as `stale`. **Every leaving player's final session was silently discarded.** | **Critical** | Fixed + `7C-S7` |
| **7C-D2** | On landscape phones `stealLift` was 16 px, putting the steal panel directly on Roblox's bottom-left thumbstick zone. | **High** | Fixed + `7C-M4` |

7C-D1 was reproduced on `8712d78` (the pre-Phase-7C source) with a probe: after
the leave, the store was **`MISSING`**; after the fix, **`present`**. This means
progression earned during a session was durable only via round-boundary payouts —
a player who caught cells and left before a round closed lost them.

---

## 2. Task 1 — shutdown persistence

### 2.1 What was wrong

There was no `game:BindToClose` at all. When a server closes for an update, a
migration, or because the last player left, Roblox does not wait for outstanding
work: `PlayerRemoving` fires, but the instance can be terminated while the
`SetAsync` it dispatched is still in flight. §1's 7C-D1 made this worse — the
final save was dropped even when the server lived on.

### 2.2 Engine constraints (validated, not assumed)

| Constraint | Value used | Source |
| --- | --- | --- |
| Signature | `game:BindToClose(function)` | Roblox API dump: `DataModel.BindToClose`, one `Function` parameter, `Security: None`, returns null |
| Grace period | **≤ 30 s**, then the instance is terminated regardless | Roblox documentation |
| Concurrency | multiple bindings may be registered and run concurrently | same |
| Behaviour in Studio | fires, but there is no DataStore to write | verified here by probe |

The drain is therefore **bounded at 20 s** (`SHUTDOWN_BUDGET`), which stays
inside the 30 s ceiling with room for one slow round trip.

### 2.3 Implementation

**`src/server/Persistence.luau`**

- `beginSave(userId)` — one place that validates writability, deduplicates, and
  claims a single-flight slot. Returns `(false, reason)`, `(true, nil)` for
  nothing-to-do, or `(true, writeFn)`.
- `save(userId)` — unchanged public contract (never yields); now returns
  `"queued"` / `"joined"` / `"unchanged"` instead of the old `"ok"`.
- `saveAwait(userId)` — for callers allowed to yield. Used by `PlayerRemoving`.
- `shutdownSave(budget)` — flushes every `Loaded` profile, waits bounded on the
  single-flight register, and returns an accurate report.
- `Persistence.equal(a, b)` — structural comparison for dedupe.
- Counters: `inflight`, `lastPayload`, `writeSerial`, `shutdownSaves`,
  `shutdownSkipped`, `shutdownFailed`, `shuttingDown`.

**`src/server/Main.server.luau`**

- `snapshotSession(userId)` — folded out of `PlayerRemoving` so the leave path
  and the shutdown path write the **same table**. Two different merge orders
  against one key is exactly how a shutdown persists less than was earned.
- `game:BindToClose(...)` — snapshots each online player, drains, then prints a
  single auditable line.

### 2.4 Requirement-by-requirement

| Requirement | How it is met | Test |
| --- | --- | --- |
| Save only confirmed-writable profiles | Only `state == Loaded` enters the drain; `beginSave` re-checks `isWritable` | `7C-S2`, `7C-S10` |
| Never save failed/uninitialised | A `Failed` or `Loading` session is excluded twice | `7C-S2` |
| Concurrent `PlayerRemoving` + `BindToClose` | Single-flight register: the second attaches, it does not race | `7C-S4` |
| No duplicate/conflicting saves | In-flight join + payload dedupe + monotonic `writeSerial` | `7C-S3`, `7C-S8` |
| Bounded wait | `os.clock()` deadline, `SHUTDOWN_POLL` loop, reports `pending` | `7C-S8` |
| DataStore failure cannot corrupt | Payload is a sanitised snapshot; a failed write never records `lastPayload`; the previous record is untouched | `7C-S5` |
| API signature + constraints validated | §2.2 | — |

### 2.5 Behaviour during shutdown

The drain prints exactly one line per shutdown:

```
[Brainrot] shutdown • 2 online, 2 writable, 2 written, 0 already saved, 0 failed, 0 pending (0.00s, store=BrainrotArenaAcceptance_<run>, memoryOnly=false)
```

Verified truthfulness in three cases:

| Case | Report |
| --- | --- |
| Two fresh players | `2 writable, 2 written, 0 failed` |
| DataStore writes fail | `2 writable, 0 written, **2 failed**` + a warning |
| Loads failed | **`0 writable`**, `0 written` |
| Studio (memory-only) | `1 writable, 0 written, 1 already saved, memoryOnly=true` |

A failed drain also emits `warn("[Brainrot] shutdown finished with N unsaved
profile(s)")`. Nothing is ever reported as written when it was not.

---

## 3. Task 2 — mobile ActionBar layout

### 3.1 Root cause

Three controls competed for one horizontal band at the bottom of the screen:

```
[ ability 118 ] [ steal 150 ]              phone, right-anchored
[      action bar 252, centred      ]
```

- A 390 px phone needs `150 + 8 + 118 + 252 = 528 px` to fit them side by side.
  It has 390. No anchor or centring choice can fix that, so **every phone
  overlapped**; 390×800, the size named in the brief, showed the bar from x=69
  to 321 sitting on top of both action panels.
- The steal panel also has a **readout 38 px above it**, so its real footprint is
  68 px tall, not 52. Clearing "the button" left the bar sitting on the readout.
- At 740–932 px a centred bar's left edge landed on the ability panel; at
  820×1180 (tablet) likewise.

### 3.2 Fix

Layout geometry is now computed **once** at the top of `Hud:resize()`, and every
control reads from it:

```lua
local STEAL_STACK = 52 + 38     -- button + readout above it
local PANEL_LIFT  = 118
local singleRowNeeds = stealW + Space.sm + barW + Space.sm + abilityW
self.twoRows = width < singleRowNeeds or width < 700
```

- **Two-row layout** (phones): the bar takes its own row, lifted by
  `PANEL_LIFT + STEAL_STACK + Space.sm`; the ability panel moves above the bar.
- **Single-row layout** (tablet/desktop): the bar is parked immediately left of
  the action cluster (`clusterLeft - Space.sm`), not centred and not at the edge.
- **Landscape phones**: `stealLift` is now `PANEL_LIFT` (was 16 px), clearing the
  thumbstick zone; the steal panel keeps its bottom-left position.

No control is hidden and every touch target keeps its 52 px height.

### 3.3 Measured result — 17 viewports, zero problems

| Viewport | Before | After |
| --- | --- | --- |
| 320×568 | steal/bar + ability/bar overlap | clean |
| 360×740 | overlap | clean |
| **390×800** | **overlap** | **clean** |
| 430×900 | overlap | clean |
| 412×915 | overlap | clean |
| **844×354** | ability/bar overlap, steal on thumbstick | clean |
| 740×360 | ability/bar overlap | clean |
| 932×430 | ability/bar overlap | clean |
| 600×400, 699×500, 700×500 | steal/ability or ability/bar | clean |
| 768×1024, 820×1180 (tablet) | ability/bar overlap | clean |
| 1024×768, 1280×600, 1280×720, 1920×1080 | partly clean | clean |

The two panes at 700 px (`699×500` and `700×500`) are both in the matrix so an
off-by-one in the threshold cannot hide.

### 3.4 Regression tests

`7C-M1` overlap · `7C-M2` on-screen · `7C-M3` ≥44 px touch targets ·
`7C-M4` thumbstick/jump clearance · `7C-M5` the row decision itself ·
`7C-M6` rotation round-trip. All measure real rectangles from the running HUD,
with the steal readout folded into the footprint.

---

## 4. Fail-on-old proof

The new tests were run against the **previous commit** (`8712d78`) with the new
test file and mock:

```
FAIL 7C-S1   shutdown saves every loaded profile       0 ~= 1
FAIL 7C-S2   never writes a profile whose load failed   0 ~= 1
FAIL 7C-S5   write failure during shutdown corrupts     assertion failed
FAIL 7C-S6   multiple players save in one shutdown      0 ~= 1
FAIL 7C-S8   shutdown is idempotent and bounded         0 ~= 1
FAIL 7C-S9   Studio shutdown honest about memory-only   0 ~= 1
FAIL 7C-S10  the report counts writes truthfully        no shutdown report emitted
FAIL 7C-M1   no bottom control overlaps                 steal(+readout) overlaps actionbar at 320x568
FAIL 7C-M4   clear the thumbstick and jump zones        steal(+readout) sits on the thumbstick at 844x354
FAIL 7C-M5   bar takes its own row only when needed     a 320 px phone must use two rows
FAIL 7C-M6   rotation keeps every control on screen     overlap after rotation to 390x800
ADAPTER RESULTS: 128 passed, 12 failed
```

Against the fixed source: **140 passed, 0 failed**.

`7C-S3`, `7C-S4`, `7C-S7` pass on both sources, which is correct and stated
rather than hidden: `S3`/`S4` assert "no more than one write", which a build
with no shutdown trivially satisfies; `S7` passes on old by accident because the
old code wrote on leave through a different path. They are kept as guards
against future regressions, not as evidence of this phase's fix.

7C-D1's proof is separate and direct: the probe writes `MISSING` on `8712d78`
and `present` after the fix.

---

## 5. Evidence classification

Kept deliberately separate, because they are not interchangeable.

### 5.1 Automated, no Roblox boundary

`tests/core.spec.luau` — pure rules: round machine, rewards, chaos rules, route
maths. **150 tests.** No engine, no services.

### 5.2 Mock-based (contract doubles)

`tests/adapters.spec.luau` — runs the **real** `Main.server`, `Persistence`,
`Hud`, `Effects` and `Main.client` against `tests/roblox_mock.luau`.
**140 tests.** This is where every Phase 7C test lives.

What the doubles model: instance tree, services, signals, DataStore `Get`/`Set`/
`Update`/`Remove`, `BindToClose` registration, `task.spawn`, GUI sizing and
anchoring, `AbsolutePosition`/`AbsoluteSize`.

What they **do not** model: physics, replication, rendering, input delivery,
audio, real DataStore latency/throttling/quotas, the engine's 30 s kill, or
concurrent execution of `BindToClose` callbacks. `env:shutdown()` runs bindings
in order and returns.

### 5.3 Real Roblox Studio / published server / device

**Not performed. Zero results.** No row of
[PHASE7B_ACCEPTANCE_PACKAGE.md](PHASE7B_ACCEPTANCE_PACKAGE.md) has been executed,
and this phase adds no engine claim. Specifically **not** proven by anything here:

- that the engine calls `BindToClose` before terminating the instance;
- that 20 s is enough on a real DataStore under throttle;
- that the layout looks right or that taps land where the geometry says;
- that `PlayerRemoving` yields safely on a real server.

---

## 6. Completion criteria — not release-ready

**The game is not declared release-ready.** Automated and mock verification is
green; the following remain unverified and must be executed manually.

### 6.1 Real server shutdown (new this phase)

Precondition: the acceptance package's §3 setup, `memoryOnly=false`.

1. Join a **published private server** with the acceptance namespace configured.
2. Confirm the start-up line says `store=BrainrotArenaAcceptance_…` and
   `memoryOnly=false`. Anything else — stop.
3. Play a full round so a payout is written, then catch cells **without**
   reaching a round boundary (so the only remaining copy is in memory).
4. Shut the server down (or let it empty), and read the
   `[Brainrot] shutdown • …` line. Record `written`, `failed`, `pending`.
5. Start a fresh server in the **same namespace** and rejoin.

| Expectation | If it fails |
| --- | --- |
| Steps 3's catches are present after the restart | `pending`/`failed` > 0 means the 20 s budget or the write itself is insufficient: raise the budget or reduce `MAX_RETRIES` |
| `pending` is 0 | a non-zero `pending` means the engine killed the drain early |
| No duplicate write warnings | would indicate a dedupe bug |

Also verify the **update** path, not just an empty server: publish a new version
while players are online, and confirm the shutdown line appears and the data
survives.

### 6.2 Real DataStore persistence

The Phase 7B set (P-00…P-09) is unchanged and still outstanding, including
P-07 (a failed load must not overwrite) and P-06 (restart).

### 6.3 Two-client multiplayer

M-01…M-11, unchanged. The shutdown line is worth observing with 2 clients: it
must report `2 writable`.

### 6.4 Actual mobile touch interaction

T-01…T-11, with attention to:

- **T-03 / T-04** — steal reachable in portrait and landscape. The geometry is
  now correct at 17 viewports, but only a device proves the tap lands.
- **T-04 specifically** — landscape steal clears the thumbstick only in
  *geometry*; Roblox's thumbstick zone is a runtime control that may be larger
  than the 110×105 box assumed here. Confirm the thumb does not fight the button.
- The two-row layout puts the shop bar higher on a phone; confirm it is still
  comfortably thumb-reachable and does not cover the play area.

---

## 7. Risks

| ID | Risk | Status |
| --- | --- | --- |
| R1 (7B) | No `BindToClose` → session tail lost on shutdown | **Closed by implementation**; engine confirmation pending §6.1 |
| R2 (7B) | Phone action bar overlaps steal/ability | **Closed** — 17 viewports clean, `7C-M1..M6` |
| R3 (7B) | Carried cells not persisted until banked | By design |
| **R4** | The 20 s budget is inside the 30 s ceiling but unverified against a real throttled DataStore; a very slow write can still be cut off | Open — §6.1 measures it |
| **R5** | `PlayerRemoving` now yields on the DataStore. If a write takes the full retry ladder (3 attempts with 1.5 s + 3 s waits) the removal handler blocks ~5 s. The player is already gone and nothing on screen waits, but a burst of leaves could queue | Open — monitor in §6.3 |
| **R6** | The thumbstick/jump clearance test assumes the 110×105 Roblox default inset | Open — §6.4 |

---

## 8. Files changed

| File | Change |
| --- | --- |
| `src/server/Persistence.luau` | `beginSave`, `saveAwait`, `shutdownSave`, `equal`; single-flight + dedupe + write serial; shutdown counters |
| `src/server/Main.server.luau` | `snapshotSession` extracted; `PlayerRemoving` awaits its save (7C-D1); `game:BindToClose` drain + report |
| `src/client/Hud.luau` | Centralised bottom-control geometry; two-row phone layout; cluster-parked bar; landscape steal lift (7C-D2) |
| `tests/roblox_mock.luau` | `DataModel.BindToClose`, `env:shutdown()`, `env.writeCounts`, live `writeFail` |
| `tests/adapters.spec.luau` | +16 tests: `7C-S1…S10`, `7C-M1…M6` (one pre-existing assertion updated for the new save reasons) |
| `docs/PHASE7C_SHUTDOWN_AND_MOBILE.md` | This report |
| `docs/PHASE7B_ACCEPTANCE_PACKAGE.md` | Shutdown + two-row layout rows (see §9) |
| `docs/TESTING.md` | Evidence classification and current counts |

No gameplay, economy, art or architecture change. The only behaviour changes are
the shutdown drain, the leave-save ordering fix, and HUD placement.

---

## 9. Gate

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

361 tests passed; 0 failed
```

Breakdown: core 150, adapters 140, export 36, art 35.
Baseline 345 (core 150, adapters 124, export 36, art 35) → +16 tests, +0 failures.

Release archive: `artifacts/BrainrotArena-Project.zip` (107 files). The archive
contains this document, so its own SHA-256 cannot be quoted here — it is recorded
in `artifacts/BrainrotArena-Project.zip.sha256` and checked by
`tools/package_release.py` (archive CRC + 107 payload hashes).

Cross-server session locking and Phase 8 remain **not started**, per instruction.
