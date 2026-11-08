# Phase 3 — Arena access and gameplay fixes

**Scope:** players could not get from the lobby into the arena. This document covers
what was actually broken, what changed, and exactly what has and has not been verified.

---

## 1. What was wrong

The Phase 2 build spawned every player on the lobby deck and relied on a single
one-shot teleport when the round phase flipped to `Playing`:

| # | Defect | Effect |
|---|--------|--------|
| 1 | The teleport ran once per phase change, on a timer-less event. | If the pivot was rejected, the player stayed in the lobby for the whole round. |
| 2 | The pivot was issued without checking the result. | `PivotTo` silently does nothing on a seated (`Sit = true`) or `PlatformStand = true` humanoid, and the server never noticed. |
| 3 | Clearance was measured with a radius from the arena centre. | The arena spawn pads sit at r ≈ 36 studs and the west dock reaches x = 94, so a "close enough" test both rejected real arrivals and accepted players standing on the causeway. |
| 4 | Nothing ran per-frame. | A character that respawned, was knocked off a bridge, reset, or joined mid-round never got a second attempt. |
| 5 | Returning to the lobby after `Results` used the same one-shot pattern. | Losing the pivot once left the player in the arena through the whole next intermission. |

Nothing here was a sign or portal problem: the entrance geometry was fine the whole
time. The transition logic itself was the fault.

## 2. What was built

### 2.1 A pure routing state machine — `src/server/core/ArenaRoute.luau`

Strict-typed, engine-free, exhaustively unit-tested. It decides *who* should be
where and *when to try again*; it performs no side effects.

- **Intent** — `desired(player)`: `arena` while the round is `Playing` and the player
  is participating; `lobby` for `Waiting`, `Intermission` and `Results`; `nil` for a
  spectator during a live round, who is never moved.
- **Where they are** — `zone(position)` uses two z-planes, not a radius:
  `z ≥ 140` is the lobby, `z ≤ 92` is the arena, everything between is the causeway
  (`transit`). Transit counts as arrived for **both** destinations, so a player
  walking the bridge is never yanked backwards or ping-ponged.
- **Retry policy** — a fresh intent attempts immediately; a failed attempt backs off
  `0.45 s`; after 4 attempts (≈ 1.8 s) the router returns `give-up`, which is the
  signal for the server's hard fallback. Attempts reset the moment the player
  arrives or the intent flips.
- **Sweeping** — `slice(n)` returns a round-robin window of `ceil(n/8)` players per
  heartbeat, so a full 12-player server is re-checked several times a second without
  costing a full scan every frame.

### 2.2 A verified, self-healing mover — `src/server/Main.server.luau`

- `movePlayer()` **verifies** every pivot: after `PivotTo` it compares the root part
  position to the target (≤ 16 studs). A silent refusal resets the backoff so the
  next heartbeat retries immediately, and increments `route.corrections`.
- Phase flips call `routePlayer(force = true)`: cooldown and attempt counters are
  cleared and a normal (non-escalating) attempt is made, so a phase change never
  jumps straight to a fallback pivot.
- **Fallback (the guarantee).** When `evaluate` says `give-up`, the server detaches
  the character from a seat (`Sit = false`), clears `PlatformStand`, confirms the
  humanoid is alive and ready, re-seats it cleanly and pivots. Each fallback bumps a
  per-player attribute, `ArenaRouteFallbacks`, and logs one line so a live issue is
  visible in the output window rather than silent:
  `[Brainrot] route fallback #2 • MintBrain -> arena (detached from seat)`.
- Joins mid-round are routed on the next heartbeat; leaving removes the track; a
  dead character is never force-pivoted (it is re-routed after `CharacterAdded`).

### 2.3 What deliberately did **not** change

- Round timing, scoring, coin payouts, pickup behaviour, rarity values, gravity
  events and the two-verb remote surface are untouched. `Request` still accepts only
  `Snapshot` and `Halo`.
- No new remotes, no teleport service, no client-side authority. Routing is decided
  and executed on the server; the client only renders the result.
- The entrance geometry (arch, banner, medallions, lanterns) is unchanged.

## 3. Verification actually performed

Run with `python3 tools/check.py` — **198 tests, 0 failed** (the numbers below are
the routing-relevant subset).

| Test | Where | What it proves |
|------|-------|----------------|
| `route: player is pulled into the arena when a round starts` | adapters | Phase flip moves a real character across the z = 92 plane. |
| `route: a character knocked back to the lobby mid-round is returned` | adapters | Per-heartbeat recovery, not a one-shot. |
| `route: a seated character that refuses a pivot still reaches the arena` | adapters | The fallback path runs and the drop is observed. |
| `route: every eligible player is transferred, not just the first` | adapters | All players moved in one round. |
| `route: players return to the lobby after the round` | adapters | Reverse direction on `Results`. |
| `route: no repeated teleport loop once a player has arrived` | adapters | Zero extra pivots after arrival (no loop). |
| `route: a respawn during a round rejoins immediately` | adapters | `CharacterAdded` re-routes at once. |
| `route: a dead character is not forcibly teleported` | adapters | No pivot while `Health = 0`. |
| `route: a fall during a round is rescued into the arena` | adapters | Y-fall rescue lands in the arena, score kept. |
| `route: a mid-round joiner is routed in and counted` | adapters | Late joiners participate. |
| `route: a joiner during intermission waits in the lobby` | adapters | No premature teleport. |
| `route: two players move consistently and independently` | adapters | Both end in the arena at their own pads. |
| `route: a player who leaves stops being routed` | adapters | Track removal on `PlayerRemoving`. |
| 10 pure unit tests (desired / zone / transit / backoff / escalation / dead respawn / idle / slice / stats) | core | The policy itself, with no engine involved. |

Multiplayer: the two-player rounds in the adapter suite (`two-player round teleports
both`, `two independent clients each render the same server roster`) run two real
server tracks against one state machine, with two clients rendering the same roster.

## 4. Honest limitations

- **All of this is verified against the mocked Roblox boundary, not the running
  engine.** The sandbox has no Roblox Studio, so engine physics, seat behaviour and
  real `PivotTo` results are simulated by `tests/roblox_mock.luau`. The mock refuses
  to skip frames, which is why every simulation steps in 0.1 s increments, but it is
  still a model.
- **Studio acceptance is still required** before shipping. The exact manual pass is
  written down in `docs/TESTING.md` (§ "Arena access"), including a seat test: sit on
  a lobby bench during the intermission and confirm the round still pulls you in.
- If a player is seated on geometry the server cannot detach them from *and* the
  character is simultaneously broken, the server logs the fallback and leaves the
  character alone rather than teleporting a corpse; the player is re-routed on their
  next respawn. This is a deliberate trade: never move a dead avatar.
