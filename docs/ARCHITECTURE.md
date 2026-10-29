# Implementation notes

## Source and export ownership

`src/` is the editable game source. `tools/world.py` defines the original environment once. `python3 tools/build_place.py` generates `src/server/WorldData.luau` and both `places/*.rbxlx` files using only Python's standard library.

Each place embeds the source in the correct Roblox services and includes a baked, editable `Workspace.BrainrotWorld` model. `WorldService` reuses that model without creating duplicates. Under an optional Rojo source workflow, it builds the same geometry at runtime instead. Rebuild the exports after modifying source; Studio edits are not automatically synchronized back to the filesystem.

The standard place is the deliverable for ordinary play. QuickTest differs only in the shared configuration's Studio-fast flag; the server honors it **only in Studio**. No plugins, API keys or asset downloads/uploads are part of the game boot process. The sky and short pickup sound reference Roblox's bundled local resources, not arbitrary asset IDs or third-party code.

## Runtime tree

```text
ReplicatedStorage
  BrainrotShared/Config                 shared constants (no authority)
  BrainrotRemotes/State                 server → clients: plain state snapshots
  BrainrotRemotes/Pickup                server → clients: validated pickup receipt
  BrainrotRemotes/Request               client → server: "Snapshot" or "Halo" only
ServerScriptService/BrainrotServer
  Main                                 server adapter; sole gameplay writer
  core/RoundMachine                    pure phase, score, result and reward authority
  core/PickupLedger                    pure atomic ownership / respawn generations
  core/MovementGuard                   pure basic horizontal movement sanity layer
  WorldService / WorldData              world construction and server spawn locations
StarterPlayer/StarterPlayerScripts/BrainrotClient
  Main                                 listeners, core UI configuration, HUD clock tick
  Hud                                  responsive panels, leaderboard, dialogs, input
  Effects                              local cell lobes, animation, sparks, sound, tint
Workspace
  BrainrotWorld                        358 baked anchored parts, 4 signs, lobby spawn
  BrainrotPickups                       48 server roots during Playing only
  BrainrotClientFX                      client-only visual models / short-lived effects
```

## Authority and lifecycle

- A non-yielding heartbeat step runs at approximately **10 Hz** using `Workspace:GetServerTimeNow()`.
- The round machine processes phase deadlines **before** collectible checks. A stalled server cannot award after the round expires.
- Positive and **negative** integer UserIds are valid; negative IDs are used by Studio's local players.
- Everyone automatically joins. One player is sufficient for solo testing. Late joiners start at zero in an active round; joins during results are not retroactively paid.
- The machine resets round points/pickup counts on the next round, preserving session coins, wins and cosmetic ownership.
- All online participants receive the base reward; positive-score ties share the winner bonus. An all-zero round has no winner.
- If the server empties, it cancels the round, clears cells and restores normal gravity. The next arrival receives a new intermission.
- Character-added handling routes respawns according to the current phase. Dead players cannot collect. Falling below Y=0 rescues the player without clearing their score; the engine's part-destruction limit remains lower at Y=-160.

## Pickups and requests

There is **no client pickup or score-submission remote**. The server owns slot positions, rarity, value, round ID, generation and respawn time. Each tick it checks living, participating players against an actual three-dimensional 4.5-stud pickup radius. Consuming a slot marks it unavailable **before** returning a receipt. No code yields between claim and score award. The next generation appears after five seconds; old generations/rounds cannot be replayed.

A short spawn/correction protection interval prevents arrival-time rewards. A horizontal displacement sanity check rejects extreme teleports and corrects the server root position; vertical jumps remain unrestricted for low gravity. This is a useful prototype safeguard, **not** a complete anti-cheat solution for a competitive public launch. Roblox character positions are still influenced by client network ownership.

`Request` accepts only a string `"Snapshot"` or `"Halo"` with **zero additional arguments**. It rate-limits requests by player/action (1 second / 0.75 seconds respectively). The client never supplies a price, amount, pickup ID, position or target player. Halo balance, ownership and equip decisions live in the round machine. A purchase is charged once; subsequent requests toggle equip state.

Snapshots contain only plain tables, arrays and primitive values. Reward dictionaries use **string UserId keys** for safe Roblox remote serialization. Name labels do not enable RichText. Score/coin/win values also appear in server-maintained `leaderstats`. Snapshots are sent at most four times a second when dirty, otherwise once a second; clients derive countdown display from server deadlines.

## Appearance and performance

Original geometry only: cylinders, wedges, blocks and six-lobed procedural brains. No toolbox packages, uploaded meshes, copyrighted meme characters, external scripts or web requests. The concept board informs palette/energy, not copied assets.

- **358** static map parts; all anchored. One map light plus lightweight lighting effects.
- **48** simple server pickup roots. Touch/query/collision disabled on pickup/decorative roots.
- Each client creates six-lobed cell models, culls distant visuals and updates bob/spin at **30 Hz**. Together, the static world + server cell roots + local cell visuals total **790 parts**, excluding avatars, optional halos and brief particles.
- Effects are cosmetic only; local bobbing never changes the server's scoring positions.
- Round cleanup destroys pickup replicas; client listeners remove the corresponding models. Temporary sparks, popups and sounds have timed cleanup.
- Mobile layout hides the full ranks list by default, exposes a toggle, and raises the score display clear of portrait thumb controls. Safe-area insets are honored. Reduced motion stops bob/spin/sparks; SFX can be muted.

## Configuration

Edit `src/shared/Config.luau` for timing, gravity, walk speed, rarity weights, coin rewards or the halo cost. Pickup denominations are intentionally also whitelisted in the authority modules: changing the denominations requires updating those rules and tests, not merely a client label.

Edit `tools/world.py` to move floor pieces, signs, cells or spawn pads consistently. `WorldData.luau` is generated and should not be hand-edited. The recommended published capacity is **8**, matching the safe spawn positions. The logical rules are additionally stress-simulated with 12 players; that is not a capacity/performance certification.

## Validation boundaries

`tools/check.py` compiles all Luau, strictly analyzes the pure authority/config modules, executes the core suite, and executes production adapters against `tests/roblox_mock.luau`. That mock provides explicit service boundaries and checks property/enum names against `tests/fixtures/roblox-api.json`, pinned to a Roblox API snapshot. It does **not** implement physics, actual networking, rendering, touch input or sound playback.

`tools/verify_place.py` checks embedded source, instance references, API property loadability, geometry support/spacing, bridge continuity, budget and the fast/standard variants. Builds are deterministic; exports must match the source. The GitHub workflow can repeat the same checks, but it has not been executed remotely in this session.

Always perform the short [Studio acceptance pass](TESTING.md) before treating the prototype as playtested or publishing it.
