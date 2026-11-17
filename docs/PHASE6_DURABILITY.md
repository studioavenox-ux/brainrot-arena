# Phase 6 — Durability Audit and Round-Scoped Rewards

Scope: diagnose, evidence and fix the defects found while inspecting the Phase 5
build. **No system was redesigned.** The authority model (pure `RoundMachine` +
thin adapter), the remote surface, the map, the UI and the art direction are
unchanged. Studio/device behaviour is still **unverified** — see the end of this
document.

Everything below was reproduced by executing the real sources against the
repository's Roblox service doubles (`tests/roblox_mock.luau`), not by reading code.

---

## 1. Findings

### 1.1 Fully implemented (verified by the automated gate)

| Area | State |
| --- | --- |
| Round lifecycle | Waiting → 12 s intermission → 180 s staged round → 9 s results, auto-repeating; stage banks, event window, teardown |
| Collection | 48 slots, atomic claim, three denominations, respawn generations, server-side distance |
| Stealing | Server-resolved target, 13 studs, 8 s cooldown, spawn protection, victim immunity, no-repeat window |
| Chaos Events | Exactly one 35 s window per round, drawn server-side, warned in advance, fully reverted |
| Characters & abilities | Six characters, switch quotas (3 + 1 Chaos-only), per-character cooldowns, six abilities, all server-validated |
| UI/HUD | Server-driven snapshot rendering, responsive desktop/tablet/phone, touch-safe bands |
| Arena routing | Destination assertion with backoff, seated/dead fallback, verified pivots, fall rescue |
| Schema integrity | `sanitise()` repairs hostile/corrupt profiles; no client-writable number exists |

### 1.2 Defects found

Ranked by severity. Each entry: reproduction → files → root cause → why the old
suite missed it → fix.

---

#### D1 — CRITICAL: a published server never persisted anything

**Reproduction** (real sources, `RunService:IsStudio() == false`):

```
Persistence.new({})  ->  memoryOnly = true, available = false, store = nil
```

A full round was then played to completion and the player removed:

```
PROBE2 phase Results   leaderstats coins 10
PROBE2 stores: 0        <- DataStoreService:GetDataStore was never called
```

**Files / functions**
- `src/server/Persistence.luau` → `Persistence.new`
- `src/server/Main.server.luau` → `local profiles = Persistence.new({})`

**Root cause** — an inverted default:

```lua
self.memoryOnly = o.memoryOnly ~= false or (RunService:IsStudio() and o.persistInStudio ~= true)
```

`o.memoryOnly` is `nil`, and `nil ~= false` is **true**, so every store constructed
without an explicit flag was memory-only. The production call passes `{}`. The
DataStore branch was therefore unreachable outside a test that named
`memoryOnly = false` by hand. Coins, the specimen log, lifetime stats and the halo
were session-only despite every document claiming otherwise.

**Why the tests missed it** — the mock defaulted to Studio context
(`options.studio ~= false`), where memory-only is *correct* behaviour, and the only
proof-of-persistence test constructed the store with `memoryOnly = false,
persistInStudio = true` and asserted on the store directly. No test exercised
`Persistence.new({})` from `Main.server` in a published-server context, so the
default value — the actual bug — was never on the tested path.

**Fix** — the flag is now explicit and defaulted correctly:

```lua
self.memoryOnly = (o.memoryOnly == true) or (o.readOnly == true)
    or (RunService:IsStudio() and o.persistInStudio ~= true)
```

A live server persists by default; Studio stays memory-only unless
`persistInStudio` is passed; `readOnly` exists for isolated tests and tooling. The
dead `self.failed[userId] = data == nil and false or false` line (always `false`)
was removed.

---

#### D2 — HIGH: round payouts re-added every earlier round's catches

**Reproduction** (published-server context; two consecutive rounds):

```
round1 starts  sessionCollection total = 0
round1 caught 4 -> sessionCollection total = 4
round2 starts  sessionCollection total = 4
round2 caught 2 -> sessionCollection total = 6
```

`Persistence.applyRound` was called with `collection = row.collection` — the
*session* record. With `applyRound` adding rather than merging, the durable
specimen log received round 1's catches again on round 2's payout. A player
playing N rounds logged a triangular sum. Because `Main.server` saved every round,
this also inflated saved data on every payout as soon as D1 was fixed.

**Files / functions**
- `src/server/core/RoundMachine.luau` → `Player`, `Row`, `Results`, `award`,
  `finishRound`, `setPhase`, `snapshot`
- `src/server/Main.server.luau` → the `phase == "Results"` payout branch

**Root cause** — one table served two different lifetimes. `collection` is the
session record the specimen log shows (deliberately spanning rounds); the payout
needs "what this round caught". No round-scoped counter existed, so the payout
used the only counter there was.

**Why the tests missed it** — the only multi-round collection test asserted that
`collection` *survives* a round boundary (correct, and still asserted), and the
payout test used a single round, where session and round totals are identical.
The defect only exists across a boundary, and only on the persistence side, which
had no multi-round test.

**Fix** — two records with one writer, and a frozen payout:

- `Player.roundCollection` / `Row.roundCollection` hold this round's catches;
  `award` is the only writer and increments both tables together.
- `finishRound` resets nothing but *freezes* `collections[userId]` into
  `lastResults`, alongside the existing `rewards`/`winners`.
- The adapter pays from `lastResults.collections` and only for ids present in
  `lastResults.rewards`, so a payout that runs late cannot record the next
  round's catches and cannot touch a player the round did not pay.
- `setPhase("Playing")` and `setPhase("Waiting")` clear `roundCollection`;
  `collection` is untouched (the specimen log still spans rounds).
- `snapshot()` sends an explicit wire row and deliberately **omits**
  `roundCollection`: bookkeeping the client never reads does not cross a remote.

---

#### D3 — MEDIUM: a refused steal silently started the 8 s lockout

**Reproduction**

```
t1  steal refused (no rival in range)  -> server logs "out-of-range"
    player.stealReadyAt = 0            -> the HUD therefore shows "STEAL READY"
t2  1.0 s later, target now in range   -> request dropped by the adapter gate
    no "steal ok" line; nothing moved
```

**Files / functions**
- `src/server/Main.server.luau` → `Request` handler, `Steal` branch
  (`record.requests.StealSent`)

**Root cause** — `StealSent` was stamped *before* the outcome was known. The
adapter gate then refused every retry for `Config.Steal.Cooldown`, while the HUD
countdown is derived from the machine's `stealReadyAt`, which the machine only
sets on a successful steal. The two disagreed for eight seconds, so the UI
promised a verb that the server silently refused — and the refused tap also cost
a rate-limit window.

**Why the tests missed it** — the steal tests asserted that a successful steal
moves a cell and that an out-of-range steal does not. Neither asserted on
`stealReadyAt` after a refusal, and no test retried a refused steal within the
cooldown.

**Fix** — `StealSent` is stamped only when `outcome == "ok"`. A refusal is
answered immediately and leaves the verb ready, which is what the machine and the
HUD already reported.

---

#### D4 — LOW: two player-facing strings contradicted the saved data

- The shop said the halo cost "**session** coins" and that ownership was "for the
  session"; the halo is persisted.
- The specimen log said `CELLS CAUGHT THIS SESSION` over `row.pickups`, but the
  machine resets `pickups` at every round start, so it is a per-round count.

Fixed in `src/client/Hud.luau` and `src/client/Collection.luau` (copy only).

#### D5 — LOW (documented, not fixed): test-harness default

`tests/roblox_mock.luau` defaulted `options.studio` to **true**. That is why D1
survived: every fixture was a "Studio server", the one context where memory-only
is correct. The mock now writes the default explicitly, with a comment, and the
new persistence tests pass `studio = false` (the published-server context) on
purpose. The default itself is unchanged, so no existing test changed meaning.

---

## 2. Severity ranking and milestone decision

| Rank | Defect | Severity | Why |
| ---: | --- | --- | --- |
| 1 | D1 persistence never enabled | **Critical** | The entire meta-progression is lost on every server; the game "works" in playtests and silently resets in production |
| 2 | D2 round-scoped specimens | **High** | Corrupts saved progression as soon as D1 is fixed; unbounded growth |
| 3 | D3 refused steal lockout | Medium | 8 s of silent, unprompted refusal on the core verb |
| 4 | D4 misleading copy | Low | Player-visible misinformation |
| 5 | D5 harness default | Low | Testing gap that hid D1 |

**Next milestone: make progression durable and correct end-to-end** — enable
persistence, make every payout round-scoped, and prove both with regression tests
that fail on the old code. That is deliberately *not* new content: no pets, eggs,
Robux, extra maps or emotes. The game already has a complete, replayable core
loop, and the only thing standing between it and a real player's saved progress
was a one-line inverted default plus the accounting that depended on it.

Recommended **following** milestone (not started): a Studio acceptance pass on a
published private server — real DataStore latency, two clients, touch layout —
which is the last unverified layer of this change.

---

## 3. What changed now

| File | Change |
| --- | --- |
| `src/server/Persistence.luau` | Correct default (persist in production, memory-only in Studio unless asked); optional `readOnly`; removed the always-false `failed` write |
| `src/server/core/RoundMachine.luau` | `roundCollection` on `Player`/`Row`; `award` increments it; `finishRound` freezes `results.collections`; round boundaries clear it; `snapshot()` builds explicit wire rows without it |
| `src/server/Main.server.luau` | Pays from `lastResults.collections`/`rewards` only; stamps `StealSent` only on a successful steal |
| `src/client/Hud.luau`, `src/client/Collection.luau` | Copy corrected to match persisted coins and the per-round catch counter |
| `tests/core.spec.luau` | +5 tests: round-scoped counting, frozen payout snapshot, two-round isolation, empty collection entry, wire row shape |
| `tests/adapters.spec.luau` | +3 tests: published server opens a store and writes on payout; two-round coins/specimens through the real adapter; refused steal leaves the cooldown at zero |
| `tests/roblox_mock.luau` | Explicit, documented Studio default (no behaviour change) |

The new tests were run against the pre-fix sources (`git archive HEAD`) to prove
they are real regressions: **3/3 adapter tests and 4/4 core tests fail there**, and
all pass here.

---

## 4. Verification actually performed

```
python3 tools/check.py
  PASS Studio place exports built
  PASS All 32 Luau files compile
  PASS Strict type analysis: authority modules + configuration
  PASS Core rules and 100 simulated 12-player rounds
  PASS Production adapters against mocked Roblox services
  PASS Place structure, loadable API properties and geometry
  PASS Art direction: palette, hierarchy, legibility, lighting rig
  PASS Deterministic export rebuild
  PASS Git diff whitespace check

329 tests passed; 0 failed
```

End-to-end re-check after the fixes (published-server context, real adapters):

```
production Persistence.new({}) -> store opened: true   available: true   memoryOnly: false
Studio      Persistence.new({}) -> memoryOnly: true    (playtests stay off the live keys)
round1 caught 4 -> round2 starts (session total 4) -> round2 caught 2
stored profile: Rounds=2  Coins=92  Specimens total=6   (true total = 6)
```

### Not verified (unchanged from Phase 5)

- **Roblox Studio was not available.** No claim here is an engine, physics,
  rendering or real-network result; the doubles are contracts, not Roblox.
- Real DataStore latency, retry/back-off and quota behaviour under load.
- Two clients on a published server, touch layout on a device, and real
  audio/resource availability.
- Whether the live DataStore accepts the profile table as written (it contains
  only strings, numbers and nested string→number tables, which is the documented
  supported shape, but it has not been round-tripped through the real service).
