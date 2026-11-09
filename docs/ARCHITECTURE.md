# Implementation notes

## Source and export ownership

`src/` is the editable game source. `tools/world.py` defines the original environment once; `tools/theme.py` defines the art direction (palette, materials, lighting rig, hierarchy layers) once. `python3 tools/build_place.py` generates `src/server/WorldData.luau`, `src/shared/ArtDirection.luau` and both `places/*.rbxlx` files using only Python's standard library. Nothing visual is hand-duplicated: the export and the runtime builder read the same tables, and `tools/artcheck.py` fails the build if the exported lighting rig drifts from `tools/theme.py`.

Each place embeds the source in the correct Roblox services and includes a baked, editable `Workspace.BrainrotWorld` model. `WorldService` reuses that model without creating duplicates. Under an optional Rojo source workflow, it builds the same geometry at runtime instead. Rebuild the exports after modifying source; Studio edits are not automatically synchronized back to the filesystem.

The standard place is the deliverable for ordinary play. QuickTest differs only in the shared configuration's Studio-fast flag; the server honors it **only in Studio**. No plugins, API keys or asset downloads/uploads are part of the game boot process. The sky and short pickup sound reference Roblox's bundled local resources, not arbitrary asset IDs or third-party code.

## Runtime tree

```text
ReplicatedStorage
  BrainrotShared/Config                 shared constants (no authority)
  BrainrotShared/ArtDirection           generated palette + lighting rig mirror
  BrainrotShared/AudioRules             pure track choice, fade step, ID and cue rules
  BrainrotRemotes/State                 server → clients: plain state snapshots
  BrainrotRemotes/Pickup                server → clients: validated pickup receipt
  BrainrotRemotes/Request               client → server: "Snapshot" or "Halo" only
ServerScriptService/BrainrotServer
  Main                                 server adapter; sole gameplay writer
  core/RoundMachine                    pure phase, score, result and reward authority
  core/PickupLedger                    pure atomic ownership / respawn generations
  core/MovementGuard                   pure basic horizontal movement sanity layer
  core/ChaosRules                      pure per-kind Chaos modifiers (gravity, friction, jump, rarity, respawn)
  EventDirector                        applies gravity and surface friction from the live
                                       Chaos modifiers, adopts new surfaces while friction
                                       is on, restores everything; never decides *when* or *which*
  Persistence                          DataStore profiles: coins, specimens, stats, halo
  WorldService / WorldData              world construction and server spawn locations
  ArtService                            applies the shared lighting rig (idempotent)
StarterPlayer/StarterPlayerScripts/BrainrotClient
  Main                                 listeners, core UI configuration, HUD clock tick
  Hud                                  responsive panels, leaderboard, dialogs, input
  Iconography                          rarity silhouettes (world marks + HUD glyphs)
  Creatures                            builds the six character Models, labels, idle/collect
  CreatureData                         GENERATED cast part tables (tools/creatures.py)
  Collection                           specimen log: six live viewports, progress, status
  Effects                              local cell models, animation, sparks, sound, tint
  Audio                                lobby / arena / Chaos music crossfades and one-shot cues
Workspace
  BrainrotWorld                        906 anchored parts + 7 sign boards, 7 signs, lobby spawn
  BrainrotCharacters                   the six character Models + plinths (the asset library)
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

`Request` accepts only a string `"Snapshot"`, `"Halo"` or `"Steal"` with **zero additional arguments**. It rate-limits requests by player/action (1 second / 0.75 seconds / 8 seconds respectively). The client never supplies a price, amount, pickup ID, position *or a steal target*. Halo balance, ownership and equip decisions live in the round machine; a purchase is charged once, and subsequent requests toggle equip state.

`Steal` is resolved entirely on the server: the adapter finds the nearest participating
player using the server's own `HumanoidRootPart` positions, then asks
`RoundMachine:trySteal(thief, victim, distance, now, roundId)`. The machine refuses a
non-live round, self-targeting, unknown or idle players, out-of-range, thief cooldown,
spawn protection, post-steal victim immunity, the same pair inside the 12-second repeat
window, and an empty carried pile — and only then moves the victim's **largest carried
cell** into the thief's *carried* pile. Both players are notified from the server's own
answer. Banked score is never touched.

## Round stages, events and persistence

- **Stages** (`Config.Stages`): Collect 0 s, Compete 45 s, Chaos 105 s, Final 150 s of a
  180 s round. Each boundary banks every player's carried cells. `RoundMachine.bank` is the
  only way a carried cell becomes permanent, and `score` is always banked + carried.
- **Chaos Event** (applied on each `Config.ServerStep`, 0.1 s; `Config.Chaos`, `Config.Timing.ChaosStart/ChaosDuration`, `Config.FastTiming` for QuickTest): exactly one 35 s
  window per round at 105 s, drawn uniformly over Low Gravity / Bouncy World / Slippery Chaos /
  Brain Cell Rush when the round starts. `RoundMachine.drawChaos` uses an injected chooser, and
  `buildSchedule` returns a single entry that carries a `WarningAt` six seconds ahead. Per-kind
  effects live in the pure `core/ChaosRules`. See [CHAOS_EVENTS.md](CHAOS_EVENTS.md).
- **EventDirector** applies gravity and walking friction from `ChaosRules.modifiers`, and
  `syncChaos()` reconciles it on every server step. Friction is written only when its value
  changes. While friction is on, a `DescendantAdded` watcher gives new surfaces (spawned or
  respawned characters, rebuilt pickups) the same friction at once. Restore writes back each
  part's recorded original and disconnects the watcher. The director moves no geometry. The
  event-only raft and path parts from earlier builds stay inert at rest. `reset()` runs on every
  phase change.
- **Audio** (`src/shared/AudioRules` + `src/client/Audio`): music follows the replicated state
  (Lobby / Arena / Chaos), crossfades over `Config.Audio.CrossfadeSeconds`, and plays stingers on
  round and Chaos edges. Every sound ID is configured in `Config.Audio` and is empty by default, so
  nothing is invented. Audio is never authoritative. See [AUDIO.md](AUDIO.md).
- **Persistence** is server-only: `sanitise()` repairs anything read from storage,
  `applyRound()` is the single place a round pays coins or increments stats, reads and
  writes retry three times inside `pcall`, and a load merges rather than replaces so a slow
  read cannot erase the session. Round score is never persisted.

Snapshots contain only plain tables, arrays and primitive values. Reward dictionaries use **string UserId keys** for safe Roblox remote serialization. Name labels do not enable RichText. Score/coin/win values also appear in server-maintained `leaderstats`. Snapshots are sent at most four times a second when dirty, otherwise once a second; clients derive countdown display from server deadlines.

## Appearance and performance

The art direction is **premium stylized low-poly tropical**: pale sand and teal stone
courts, tropical greens, a soft blue late-afternoon sky with warm sun and haze, timber
and canvas props, and a single pink/gold brain beacon as the focal point. Saturated
pink / gold / prism hues are reserved for gameplay objects, the beacon and UI. The
full rationale, palette and before/after renders are in
[VISUAL_CHANGES.md](VISUAL_CHANGES.md).

Original geometry only: cylinders, balls, blocks and character assemblies of those
primitives. The six characters are also baked into the place as editable Models —
see [CHARACTERS_PHASE4.md](CHARACTERS_PHASE4.md). No toolbox packages, uploaded
meshes, copyrighted meme characters, external scripts or web requests.

- **Hierarchy is explicit data**, not a convention: every part is classified into
  layer 1 ground, 2 nature/rock, 3 built prop or 4 hero object in `tools/world.py`,
  and `tools/artcheck.py` asserts saturation increases across those layers.
- **Materials**: 14 in use (`Sand, Sandstone, Limestone, Marble, Rock, Basalt,
  Slate, Pebble, Grass, LeafyGrass, WoodPlanks, Fabric, SmoothPlastic, Neon`).
- **906** static map parts (824 map + **82 Phase 5 event parts**), all anchored
  (913 instances in the place: 7 extra non-colliding board layers carry the sign
  `SurfaceGui`s). `CastShadow` is authored per part — 410 cast, and neon never does.
  Built structures live in `tools/terrain_aug.py` and the event geometry in
  `tools/events.py`; both use the same primitive vocabulary as the terrain. Every
  event part is **non-colliding at rest**, so a parked raft can never trap a player
  and a hidden vanishing span can never be walked on.
- **48** simple server pickup roots. During `BrainCellRush` the server drops the
  respawn to 1.5 s and to 2 s during the Final Rush; the pickup roots themselves and
  the claiming rules are unchanged. Touch/query/collision disabled on pickup and
  decorative roots.
- Each client builds one of **six original characters** per cell from the generated
  `CreatureData` table (the species chosen server-side per slot, arriving in the
  receipt), culls visuals beyond 150 studs and updates bob/spin at **30 Hz**. Models are
  rebuilt only when a cell's rarity changes; rarity marks (ring / crossed arms) are
  allocated lazily, so +1 cells cost no extra parts. Static world + server cell roots
  + worst-case local visuals total **1,496 parts**, excluding avatars, optional halos
  and brief sparks.
- **7 point lights**, all shadowless and attached to landmarks (beacon, gate, four
  satellite masts). Post-processing is limited to Sky, Atmosphere, Bloom (intensity
  0.22, threshold 1.45) and a neutral ColorCorrection — no depth of field, blur or
  sun rays.
- Effects are cosmetic only; local bobbing never changes the server's scoring
  positions.
- Round cleanup destroys pickup replicas; client listeners remove the corresponding
  models. Temporary sparks, popups and sounds have timed cleanup.
- Mobile layout hides the full ranks list by default, exposes a toggle, and raises the
  score display clear of portrait thumb controls. Safe-area insets are honored.
  The phone top bar is *derived*, not hard-coded: the coin chip is sized first, the
  clock takes whatever width the cell and coin chips leave (with a legibility floor),
  the specimen chip mirrors the coin chip's width, and the RANKS chip sits under it.
  Message bands (toast, event banner, lobby card) are placed either in the corridor
  between the cell chip and the right-hand stack or stacked below the whole top
  block, whichever the viewport actually has room for. `tools/uidraw.py` mirrors
  these rules line for line, and an adapter test asserts no two top controls overlap
  at five viewports.
  Reduced motion stops bob/spin/sparks; SFX can be muted.

## Configuration

Edit `src/shared/Config.luau` for timing (`Timing`, `FastTiming` for QuickTest), the Chaos pool and balance (`Chaos`), sound IDs (`Audio`, empty by default), gravity, walk speed, rarity weights, coin rewards or the halo cost. Pickup denominations are intentionally also whitelisted in the authority modules: changing the denominations requires updating those rules and tests, not merely a client label.

Edit `tools/world.py` to move floor pieces, signs, cells or spawn pads consistently, and `tools/theme.py` for palette, materials, lighting and lights. `WorldData.luau` and `ArtDirection.luau` are generated and should not be hand-edited; `tools/preview.py` re-renders the review plates from the same tables. The recommended published capacity is **8**, matching the safe spawn positions. The logical rules are additionally stress-simulated with 12 players; that is not a capacity/performance certification.

## Validation boundaries

`tools/check.py` compiles all Luau, strictly analyzes the pure authority/config modules (including `ChaosRules` and `AudioRules`), executes the core suite, and executes production adapters against `tests/roblox_mock.luau`. That mock provides explicit service boundaries and checks property/enum names against `tests/fixtures/roblox-api.json`, pinned to a Roblox API snapshot. It now also emits `DescendantAdded` when a subtree is parented, as Roblox does. It does **not** implement physics, actual networking, rendering, touch input or sound playback.

`tools/verify_place.py` checks embedded source, instance references, API property loadability, geometry support/spacing, bridge continuity, materials/shadows/lights, budget and the fast/standard variants. `tools/artcheck.py` checks the design rules (saturation ceilings, hierarchy order, purple/cyan restriction, lighting values, cell-vs-floor contrast, signage contrast) and freezes the collidable geometry, pickups and spawns against `tests/fixtures/world-baseline.json`. Builds are deterministic; exports must match the source. The GitHub workflow can repeat the same checks, but it has not been executed remotely in this session.

Always perform the short [Studio acceptance pass](TESTING.md) before treating the prototype as playtested or publishing it.
