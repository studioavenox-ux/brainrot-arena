# Chaos Events

Every round has **exactly one** Chaos Event. It is drawn by the server when the round
starts, uniformly from four kinds, and runs for **35 seconds**. Events never overlap.

| Kind | Name shown | What it does | Balance value (`Config`) |
|---|---|---|---|
| `LowGravity` | LOW GRAVITY | Workspace gravity drops for floaty jumps | `Chaos.LowGravity = 62` (normal 196.2) |
| `BouncyWorld` | BOUNCY WORLD | Every character's jump power is multiplied | `Chaos.BouncyJumpScale = 1.8` |
| `SlipperyChaos` | SLIPPERY CHAOS | Surfaces lose grip for the window | `SlipperyFriction = 0.06` |
| `BrainCellRush` | BRAIN CELL RUSH | Rare and Prismatic cells are weighted higher and respawn faster | `Chaos.RushRarityScale = 3`, `RushRespawn = 1.5` s |

## Timing

| | Standard place | QuickTest (Studio only) |
|---|---|---|
| Round | 180 s | 50 s |
| Warning (`INCOMING` banner) | 6 s before the window | 3 s before the window |
| Window start | 105 s (inside the Chaos stage) | 8 s |
| Window length | **35 s** | **35 s** |
| Window end | 140 s | 43 s |

The window always fits inside its round; a configuration that does not is rejected when
the round machine is created.

**Lifecycle precision.** The server's authority step runs every `Config.ServerStep` (0.1 s). Each
edge is applied on the first step at or after its scheduled time, so the window starts within one
step of 8 s (or 105 s) and ends within one step of its end. Its length is exactly 35 s. An earlier
version reset the step accumulator to zero, which made the step period drift with frame timing and
shortened the window to about 34.98 s. The accumulator now carries the remainder forward, capped at
one step.

## Server authority

* **Selection** happens in `RoundMachine.drawChaos` through an injected chooser. The live
  server passes its own RNG, clamped to the pool. A kind is never chosen by the client.
* **Rules** are data. `src/server/core/ChaosRules.luau` maps a kind to a complete set of
  modifiers (gravity, friction, jump scale, rarity scale, respawn). Every value is read from
  `Config`, and an unknown kind is an error.
* **Application** happens in `Main.server` through `syncChaos()`. It runs on every server step
  and reconciles the world to `ChaosRules.modifiers(machine.eventKind)`. It does not
  rely on remembering to undo one effect, so a dropped effect cannot leave the world altered.
* **Clients** only render the kind and remaining time that the server sends.

## Cleanup

* **Gravity** returns to `NormalGravity` from the neutral modifier set.
* **Friction** is overridden per surface. The first override records every part's *original*
  `CustomPhysicalProperties`, and restore writes those exact values back (or `nil`). Parts
  destroyed during the window are skipped.
* **Characters that arrive mid-event get the same friction.** While friction is on, a
  `DescendantAdded` watcher on `Workspace` records and overrides every new surface, so a
  character that spawns or respawns during Slippery Chaos slides like everyone else. The
  watcher is disconnected when friction is restored, so later spawns are untouched.
* Friction is written only when its value changes, never once per tick.
* **Jump power** is recomputed from the live modifier set for every humanoid, including
  respawned characters. Jump scale 1 restores the configured `JumpPower`.
* **Rarity and respawn** return to normal when the event ends, because `PickupLedger` takes
  its rarity scale and respawn from the same reconciled state.
* Every phase change (`Waiting`, `Intermission`, `Results`) also calls `EventDirector.reset()`.

## Retired content

The earlier survival schedule (two windows per round) and the `MovingPlatforms` and
`VanishingPaths` wildcards are no longer scheduled. Their baked map geometry (three orbit
rafts and four vanishing spans, all non-colliding at rest) is still present and stays parked
at its rest pose. It is no longer animated or made solid. Removing those 82 parts changes the
approved art-direction budget, so that removal is a separate decision.

Earlier phase reports (`PHASE5_STEAL_AND_EVENTS.md`, `TEST_REPORT_PHASE5.md`) describe the
superseded schedule. They are kept as historical records.

## Tests

* `tests/core.spec.luau`: the pool is exactly four kinds; one kind per round; the chooser is
  clamped; the window is 35 s and opens and closes once; a warning precedes it; it cannot
  reopen; a new round redraws; invalid configurations are rejected; each kind changes only
  its own property; Brain Cell Rush measurably raises rare odds. The QuickTest timing (50 s
  round, 8 s start, 35 s event, 3 s warning) and the normal timing (105 s, 35 s, 6 s warning) are
  asserted explicitly.
* `tests/adapters.spec.luau`: the real server and HUD. The drawn event activates at 8 s and
  closes after 35 s; exactly one open and one close per round; Bouncy World changes live jump
  power, including after a respawn; Slippery Chaos changes and restores floor friction; the
  banner shows the name and a countdown; the director restores gravity and friction exactly.
  Characters that spawn or respawn during Slippery Chaos get the friction, and the watcher is
  removed afterwards. Friction is written once, not on every tick.
* A **live-server** test runs the real `Main.server` flow (no director stubs): a respawned
  character and a late joiner are slippery during the window, and every part is restored after it.
  A mutation check that disables the watcher makes these tests fail.
* A **lifecycle** test steps the server in 10 ms increments and measures the server's own gravity
  edges: the window lasts 35 s and its edges fall on the first step at or after 8 s and 43 s.

Studio is not available in this environment. Physics feel, the banner's look, and the
behaviour of jump and friction in the real engine have not been observed. They belong in the
Studio acceptance pass.
