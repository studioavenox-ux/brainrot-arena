# Phase 7A — Persistence Safety and Test DataStore Isolation

Base: `1084385` (Phase 6), 329 automated tests passing.
This phase is a data-integrity change only. No gameplay, economy, map, UI or
art change; Phase 6 behaviour is preserved.

**Roblox Studio and a published server were not available in this environment.**
Everything below was executed against the repository's Roblox service doubles,
which are contracts, not the engine. Nothing here is an engine, physics,
replication or real-DataStore result.

---

## 1. Root cause

`Persistence.load` seeded the cache with a default profile and, on failure,
marked the player loaded anyway:

```lua
self.profiles[userId] = table.clone(DEFAULTS)   -- writable from the start
...
self.loaded[userId] = true                      -- set even when every read threw
```

`Persistence.save` then wrote whatever the cache held:

```lua
local profile = self.profiles[userId]
local payload = Persistence.sanitise(profile)
... self.store:SetAsync(key, payload)
```

There was no notion of *whether the profile was ever established*. A read that
failed (throttle, outage, quota) left an empty default in the cache, and the next
save — round payout, halo purchase, or `PlayerRemoving` — wrote that default over
the real record. The same gap let an in-flight read complete **after** a player
had left and re-create a writable profile for a session that no longer existed.

Measured on the pre-fix source (`git archive 1084385`), against a store holding a
veteran profile with **5000 coins / 120 rounds**:

| Path | Pre-fix result | Verdict |
| --- | --- | --- |
| Read fails, then save | coins 0, rounds 0 | **wiped** |
| Save fires while the read is in flight | coins 0, rounds 0 | **wiped** |
| Player leaves, late read lands | profile for the departed player re-created, save accepted | **resurrected** |

---

## 2. Implementation

### 2.1 Explicit load states (`src/server/Persistence.luau`)

`self.states[userId]` is one of `Loading`, `Loaded`, `Failed`, `Leaving`.

| Situation | State | Writable |
| --- | --- | --- |
| Read in flight | `Loading` | no |
| `GetAsync` returned a record | `Loaded` | yes |
| `GetAsync` returned `nil` (confirmed new player) | `Loaded` | yes — a default is the real record |
| Every read attempt threw | `Failed` | **no** |
| `release()` called (player left) | `Leaving` | no |
| Memory-only store (Studio, tooling) | `Loaded` | yes — nothing durable exists to lose |

`Persistence:isWritable(userId)` is the single rule; `save` refuses with
`"not-ready"` otherwise and counts the refusal, and it never mutates the in-memory
profile. Only a `Loaded` profile can reach `SetAsync`.

### 2.2 Race and departure safety

Each session claims a monotonic `generations[userId]`. The async read and the
async write both compare it before touching anything, and `release` bumps it.
A completion that belongs to a previous generation is dropped: it cannot store a
profile, cannot call the load callback, and cannot resurrect a departed session.
`release` also drops the cache entry, so a fast rejoin starts a clean generation.

### 2.3 Adapter (`src/server/Main.server.luau`)

- `playerAdded` seeds the session only from a `Loaded` profile, logs a warning for
  a `Failed` one, and performs **one** bounded retry
  (`Config.PersistenceRetryDelay`, 5 s) if the player is still present.
- `PlayerRemoving` writes the final session only when `isWritable` is true, then
  calls `profiles:release` so in-flight work is abandoned.
- The halo purchase saves only through `isWritable`.
- The round payout path is unchanged from Phase 6 and already consults
  `profiles:profile`; it now simply never gets a writable shell.

### 2.4 Behaviour during a temporary outage (documented requirement)

A player joining while the DataStore is throttled or down plays normally. Their
in-memory coins, specimen log and stats update as usual, but **no write is
attempted** for that session: offline progress is not saved, and previously saved
progress is not touched. One retry after 5 s may promote the session to `Loaded`,
after which normal saving resumes. If the retry also fails, the session stays
unsaved until the next join. Nothing is merged or invented, so the store can only
ever hold a record that was genuinely read (or genuinely new).

### 2.5 Test DataStore namespace (Task 2)

`Persistence.resolveStoreName(options)`:

| Input | Result |
| --- | --- |
| no `storeName`, no `acceptance` | `BrainrotArenaProfiles` (production, unchanged) |
| `storeName = "BrainrotArenaAcceptance_<run>", acceptance = true` | accepted |
| `storeName = "BrainrotArenaProfiles", acceptance = true` | **error** |
| acceptance prefix without `acceptance = true` | **error** |
| bare prefix, empty suffix, unknown name, non-string | **error** |
| `acceptance = true` with no `storeName` | **error** (never falls back to production) |

Resolution is server-side only. `Main.server` reads an optional
`ServerStorage/BrainrotPersistenceConfig/AcceptanceRunId`:

```lua
local Storage = game:GetService("ServerStorage")
local config = Instance.new("Configuration")
config.Name = "BrainrotPersistenceConfig"
local runId = Instance.new("StringValue")
runId.Name, runId.Value = "AcceptanceRunId", "p7a-2026-11-17"
runId.Parent = config
config.Parent = Storage
```

With it, the server prints the namespace it selected at start-up and uses
`BrainrotArenaAcceptance_p7a-2026-11-17`. Without it the published game uses
production. Player keys (`p_<userId>`) and the profile schema are unchanged, so
existing records keep working.

---

## 3. Files changed

| File | Change |
| --- | --- |
| `src/server/Persistence.luau` | Load states, generations, `load`/`save`/`release`/`forget`/`state`/`isWritable`, namespace resolution, extended `stats()` |
| `src/server/Main.server.luau` | Server-side namespace selection; state-aware seeding with one bounded retry; guarded final save and halo save; `release` on leave |
| `src/shared/Config.luau` | `PersistenceRetryDelay = 5` |
| `tests/adapters.spec.luau` | 9 new tests (A–H plus an end-to-end outage test); one existing test updated to load before writing |
| `tests/roblox_mock.luau` | `ServerStorage`, value-object defaults, `readFail`/`writeFail`, `deferAsync`/`flushAsync` |
| `tests/fixtures/roblox-api.json` | Added `StringValue`, `NumberValue`, `BoolValue`, `ObjectValue`, `Configuration`, `ServerStorage` (each verified against the official API dump blob `a4cce04…`); no existing entry changed |
| `docs/ARCHITECTURE.md`, `docs/KNOWN_LIMITATIONS.md`, `tools/package_release.py` | State model, outage behaviour, limitation 11b, new report in the release manifest |

---

## 4. Tests

Nine new adapter tests. A–G map to the required matrix; H covers isolation.

| Test | Requirement |
| --- | --- |
| `7A-A` | existing profile + successful load + save round-trips |
| `7A-B` | confirmed `nil` read = new player, default is writable |
| `7A-C` | failed read refuses the save and never overwrites the record |
| `7A-D` | save before load completion is refused; succeeds after the read lands |
| `7A-E` | leave during a pending load: no resurrection, no write; rejoin starts clean |
| `7A-F` | failed load → explicit retry → `Loaded` → save works |
| `7A-G` | failed write leaves the in-memory profile intact; next save writes the right value |
| `7A-H` | acceptance namespace isolated; production selection refused in every spelling |
| `7A-end-to-end` | join during an outage cannot wipe a veteran profile through the real adapter |

### 4.1 Original-source results

The suite was run against the pre-fix source (`git archive 1084385` with the new
tests): **9 failures, 0 false passes**, including every data-loss test and the
end-to-end wipe test. Because several tests call API that did not exist yet
(`state`, `isWritable`, `release`), the *behavioural* claim was proved separately
with probes written against the **old** module's own API:

```
pre-fix, C: failed read then save        -> Coins: 0    Rounds: 0     WIPED: true
pre-fix, D: save before load completed   -> Coins: 0    Rounds: 0     WIPED: true
pre-fix, E: late load after leave        -> resurrected: true
post-fix, C -> save accepted: false (not-ready) | Coins: 5000 | preserved: true
post-fix, D -> save accepted: false             | Coins: 5000 | preserved: true
post-fix, E -> resurrected: false               | save accepted: false
```

---

## 5. Final automated gate

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

338 tests passed; 0 failed
```

Breakdown: core 150, adapters 117 (108 + 9), export 36, art 35.
Baseline was 329 (core 150, adapters 108, export 36, art 35); +9 tests, +0 failures.

---

## 6. Remaining Studio acceptance requirements

Not performed here, and not claimed:

1. **Real DataStore round-trip** in a published place: verify `SetAsync` accepts
   the profile table (strings, numbers, nested `string → number` only) and that a
   restart with the same acceptance run id reloads it.
2. **Outage drill** on a live server: force a read failure (e.g. temporarily use a
   separate place with a restricted key) and confirm the player keeps playing, the
   record is unchanged, and the retry promotes the session when the store returns.
3. **Namespace drill**: set `AcceptanceRunId`, confirm the start-up line names the
   acceptance store, confirm production keys are untouched, and confirm that
   passing the production name with `acceptance = true` aborts as designed.
4. Two-client multiplayer, touch layout and audio remain from the Phase 5/6
   pending matrix and are unaffected by this change.

Cross-server session locking is deliberately **not** implemented; it is the next
durability step, and `UpdateAsync` is already available in the test double.
