# Phase 7B — Roblox Studio acceptance report

Continuation of Phase 7A from commit `34b6fc5` (338 automated tests).
Branch: `arena/0f1a67b1-brainrot-arena`.

Companion document: [PHASE7B_ACCEPTANCE_PACKAGE.md](PHASE7B_ACCEPTANCE_PACKAGE.md)
— the setup, the namespace format, and the 32 executable test rows.

---

## 1. Decision

# CONDITIONALLY ACCEPTED — pending engine execution

Not accepted, because **no acceptance row has been executed in Roblox Studio**.
Roblox Studio cannot run in this environment: it is a Linux container with no
Studio installation, no Rojo, and no Roblox control connector. Neither can a
published private server be created or joined from here.

The condition for acceptance is therefore narrow and explicit:

> Meta: all 32 rows in the package document are executed, recorded with evidence,
> and the rows marked `FAIL` are fixed or formally accepted as risk.

What *has* been done, and what justifies "conditionally" rather than "blocked":

| Area | Status | Basis |
| --- | --- | --- |
| Gameplay, world, art, packaging | **Conditionally accepted** | Full automated gate green; no Phase 7B change to gameplay |
| Persistence safety (Phase 7A guarantees) | **Conditionally accepted** | Proven by contract tests and pre-fix reproduction; engine proof outstanding (P-07) |
| **Mobile landscape steal** | **Accepted with a fix** | A real defect was found by measuring the layout, fixed, and proven fail-on-old |
| Touch reachability on phone | **Accepted — no defect found** | All controls in bounds at 6 viewports; rotation round-trip clean |
| DataStore durability across restart | **Risk R1** | No `BindToClose`; needs P-06 to quantify |
| Multiplayer replication / physics / audio | **Blocked** | No engine |

The game is **not** "accepted", and this document does not claim any engine
result.

---

## 2. Repository verification

| Check | Result |
| --- | --- |
| Branch | `arena/0f1a67b1-brainrot-arena` |
| HEAD at start | `34b6fc5` — *Phase 7A: fail-closed persistence and isolated acceptance DataStore* |
| Working tree at start | **clean** (`git status --short` empty) |
| Remote in sync | `34b6fc5d5ed8009ae269be0b2d10c39e0eb5af0c` on both local and `origin` |
| Phase 7A report read | `docs/PHASE7A_PERSISTENCE_SAFETY.md` — 338 tests, 3 data-loss paths closed |
| Toolchain | `.tools/luau-0.744` present (not persisted; rebuilt with `tools/bootstrap_luau.py`) |

### 2.1 Acceptance namespace configuration — verified

Read from source, then **executed** as a path (not just read):

`Persistence.resolveStoreName` refuses, by `error()`, every route to production
during an acceptance run:

| Request | Behaviour |
| --- | --- |
| `acceptance = true` with no `storeName` | error — cannot fall back to production |
| `BrainrotArenaProfiles` + `acceptance = true` | error — explicit refusal |
| any other unprefixed name | error |
| `BrainrotArenaAcceptance_` with an empty run id | error |
| non-string `storeName` | error |
| no options | production, no acceptance |

Selection is server-side only, via
`ServerStorage/BrainrotPersistenceConfig/AcceptanceRunId` (StringValue).

### 2.2 Can production be selected accidentally? — No

Verified by running the **real `Main.server`** in four contexts and recording
which DataStore namespaces were actually opened:

| Context | `AcceptanceRunId` | Namespaces opened | `memoryOnly` |
| --- | --- | --- | --- |
| Published | absent | `BrainrotArenaProfiles` | false |
| Published | `p7b-2026-11-17` | **`BrainrotArenaAcceptance_p7b-2026-11-17` only** | false |
| Studio | absent | *(none)* | true |
| Studio | `p7b-2026-11-17` | *(none)* | true |

There is no client path: no remote, attribute or property reaches the setting.
An empty value and a wrong-typed value are both ignored rather than half-applied
(`7B-NS-3`). **This is the strongest available evidence short of an engine run,
and it is now locked by tests** — before this phase, `7A-H` proved the rule but
nothing proved the server's use of it. That gap is closed (`7B-NS-1..4`).

### 2.3 The constraint that shapes the whole plan

`Persistence.new` is memory-only when `RunService:IsStudio()` is true, and
`Main.server` never opts out. Therefore:

- **Studio playtest cannot test durability.** It writes nothing, so it cannot
  prove or disprove saving. Persistence acceptance **requires** a published
  private server.
- Studio playtest is exactly right for multiplayer, gameplay, touch and HUD — and
  cannot touch real progression there even by mistake.

This is enforced by `7B-NS-4`, so if it ever changes, the gate fails and the
acceptance plan is known to be out of date instead of silently wrong.

---

## 3. Defects found in this phase

Only verified defects are listed. Evidence is a failing test on the pre-fix
source, not an opinion.

### 7B-D1 — A landscape phone cannot reach the steal button (High) — FIXED

**Symptom.** On an 844×354 (or any `height < 520`, `width < 780`) phone, the
steal button's real rectangle was `x = -174, y = 286, 186×52`. Only 12 px was on
screen, so the game's only offensive verb was effectively unreachable in
landscape.

**Cause.** `Panels.stealPanel` builds the root right-anchored
(`AnchorPoint = Vector2.new(1, 0)`). `Hud:resize()` had two branches:

```lua
if short then
    self.steal.root.Position = UDim2.fromOffset(Space.md, ...)  -- left edge
else
    self.steal.root.Position = UDim2.new(1, -Space.md, 1, ...)  -- right edge
end
```

The `short` branch positions from the left edge but keeps the right anchor, so
the panel's right edge landed at `Space.md = 12` and it extended 186 px leftwards
to `-174`. The ability panel in the same function **did** reset its anchor per
branch, which is why only steal was wrong — and why the defect survived until the
layout was measured numerically.

**Fix.** Reset the anchor in both branches, matching what the ability panel
already did:

```lua
if short then
    self.steal.root.AnchorPoint = Vector2.new(0, 0)
    self.steal.root.Position = UDim2.fromOffset(Space.md, height - stealLift - 52)
else
    self.steal.root.AnchorPoint = Vector2.new(1, 0)
    self.steal.root.Position = UDim2.new(1, -Space.md, 1, -stealLift - 52)
end
```

**Before / after**, measured on the real `Hud`:

| Viewport | Before | After |
| --- | --- | --- |
| 844×354 | `-174, 286` — **off screen** | `12, 286` — fully reachable |
| 740×360 | off screen | on screen |
| 390×800 (portrait) | `228, 630` | `228, 630` (unchanged) |

**Regression proof.** `7B-MOB-1` and `7B-MOB-2` fail on the pre-fix source with
`steal button off screen at 844x354 -> -174,286 186x52` (2 failed, 122 passed),
and pass after the fix (124 passed). Rotation round-trip
`390×800 → 844×354 → 390×800 → 354×844 → 844×354` keeps all three action panels
on screen.

### 7B-D2 — The acceptance config path was untested (Medium) — FIXED

`7A-H` tested `Persistence.resolveStoreName` directly. Nothing tested that
`Main.server` reads `ServerStorage`, builds the namespaced options, and opens
**only** that store. The acceptance procedure in §3.2 depends entirely on that
plumbing. Five tests now cover it, including a full server-restart round trip
(`7B-RESTART`): a round payout written by one server instance is read back by a
second instance over the same acceptance namespace.

---

## 4. Risks — verified but not fixed in this phase

### R1 — No `BindToClose`; a server shutdown may drop the tail of a session

`Main.server` saves on `PlayerRemoving`, on round payout, and on halo purchase.
It registers **no** `game:BindToClose`. Roblox allows ~30 s after shutdown begins;
`Persistence:save` performs `SetAsync` inside `task.spawn` with up to 3 attempts
and inter-attempt waits of `RETRY_DELAY × attempt`, which can exceed that window.

**Exposure is bounded**: each round's payout is written at the `Results` edge, so
everything up to the last completed round is durable. What can be lost is coins
earned *after* the last Results edge, plus the final `Specimens` merge in
`PlayerRemoving`.

**Why not fixed here:** it is a durability change of the same class as Phase 7A,
and it needs its own fail-on-old tests (a shutdown path in the mock). Adding it
inside an acceptance-preparation phase would mix a code change with the run that
is supposed to measure the code. It is recorded, ranked, and assigned to a
follow-up. **P-06 must quantify it before acceptance is lifted.**

### R2 — Phone action bar overlaps the steal/ability panels (cosmetic, unresolved)

At every phone width, the 252 px centred `ActionBar` shares the `barLift` band
with `StealPanel` and `AbilityPanel`. Geometric overlap is confirmed. Because the
bar is `ZIndex` 4 and its buttons are 3 while the steal button contents are 4–5,
the readable parts of the steal button remain on top; the overlap is mostly
transparent framing, but it is **not proven** that no tap is intercepted.

`T-03`, `T-04` and `T-10` are written specifically to settle this on a device.
If any tap is lost, R2 becomes a defect, not a risk.

### R3 — Carried cells are not persisted until they are banked

By design (Phase 5/6): carried cells are stealable and only become durable when a
stage boundary banks them or the round pays out. A player who disconnects mid-carry
loses what they were carrying. This is intended gameplay, recorded so it is not
later mistaken for a persistence bug during P-05/P-06.

---

## 5. Test inventory

32 rows, all shipped as `BLOCKED — no engine (7B)`:

| Section | Rows | IDs |
| --- | --- | --- |
| Multiplayer | 11 | M-01 … M-11 |
| Persistence | 10 | P-00 … P-09 |
| Mobile / touch | 11 | T-01 … T-11 |

Two of those rows double as preconditions: the start-up lines (§3.6) are recorded
before any persistence row, and **P-00 gates the whole persistence section** —
if it does not show the acceptance namespace with `memoryOnly=false`, the section
stops.

Each row carries: identifier, setup, expected result, actual, PASS/FAIL/BLOCKED,
and evidence source. A row without evidence cannot be recorded as PASS.

**None has been executed.** No engine result is claimed anywhere in this
document, and no row may be marked PASS on the basis of a mocked run.

---

## 6. Automated evidence actually obtained

`python3 tools/check.py` at the commit under test:

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

`338 → 345` (+7): `7B-NS-1..4`, `7B-RESTART`, `7B-MOB-1..2`. Zero failures.

Exact figures verified during preparation, so the manual rows quote real
expected values rather than approximations:

| Quantity | Verified value |
| --- | --- |
| Payout per player | `10 + 2 × score`, `+30` if top score |
| Worked example (measured) | winner with 7 cells → **54** coins; 3 cells, no win → **16** |
| Pickup slots | 48 (`[Brainrot] v0.2.0 ready • STANDARD • 48 pickup slots • 180s rounds`) |
| Round timing | Intermission 12 s, Round 180 s, Results 9 s |
| QuickTest timing | 4 / 50 / 5 s, chaos at 8 s for 35 s |
| Touch control heights | Steal/Ability/ActionBar all 52 px (≥ 44 px floor) |
| Layout breakpoints | `compact < 780`, `short < 520`, `narrow < 380` |

---

## 7. Outstanding work, in order

1. **Execute the package.** Mobile first (T-04 is this phase's regression), then
   multiplayer, then persistence on a private server.
2. **P-06 quantifies R1.** If the tail loss is unacceptable, `BindToClose` becomes
   the next milestone — with its own fail-on-old test.
3. **Settle R2** from T-03/T-04/T-10 tap behaviour.
4. Only then: lift the conditional status to accepted.

Cross-server session locking and Phase 8 remain **not started**, as directed.

---

## 8. Summary of files changed in Phase 7B

| File | Change |
| --- | --- |
| `src/client/Hud.luau` | Reset `StealPanel` anchor in the short-landscape branch (7B-D1) |
| `tests/adapters.spec.luau` | +7 tests: `7B-NS-1..4`, `7B-RESTART`, `7B-MOB-1..2` |
| `docs/PHASE7B_ACCEPTANCE_PACKAGE.md` | Setup, namespace format, 34-row checklist |
| `docs/PHASE7B_ACCEPTANCE_REPORT.md` | This report |
| `places/*.rbxlx`, `artifacts/*` | Regenerated by the deterministic build (ZIP SHA-256 `0c02fcd5…`) |
| `docs/KNOWN_LIMITATIONS.md` | Records risks R1 (`BindToClose`) and R2 (phone bar overlap) as 11d / 11c |
| `docs/TESTING.md` | Points at the Phase 7B package as the current acceptance matrix |

No gameplay, economy, art or architecture change. The only production change is
two lines of HUD anchoring that were provably wrong.
