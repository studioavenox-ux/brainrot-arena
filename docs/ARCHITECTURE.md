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
  BrainrotRemotes/State                 server → clients: plain state snapshots
  BrainrotRemotes/Pickup                server → clients: validated pickup receipt
  BrainrotRemotes/Request               client → server: "Snapshot" or "Halo" only
ServerScriptService/BrainrotServer
  Main                                 server adapter; sole gameplay writer
  core/RoundMachine                    pure phase, score, result and reward authority
  core/PickupLedger                    pure atomic ownership / respawn generations
  core/MovementGuard                   pure basic horizontal movement sanity layer
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
Workspace
  BrainrotWorld                        824 anchored parts + 7 sign boards, 7 signs, lobby spawn
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

`Request` accepts only a string `"Snapshot"` or `"Halo"` with **zero additional arguments**. It rate-limits requests by player/action (1 second / 0.75 seconds respectively). The client never supplies a price, amount, pickup ID, position or target player. Halo balance, ownership and equip decisions live in the round machine. A purchase is charged once; subsequent requests toggle equip state.

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
- **824** static map parts, all anchored (831 instances in the place: 7 extra
  non-colliding board layers carry the sign `SurfaceGui`s). `CastShadow` is authored
  per part — 410 cast, and neon never does. Built structures live in
  `tools/terrain_aug.py` and use the same primitive vocabulary as the terrain.
- **48** simple server pickup roots. Touch/query/collision disabled on pickup and
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
  Reduced motion stops bob/spin/sparks; SFX can be muted.

## Configuration

Edit `src/shared/Config.luau` for timing, gravity, walk speed, rarity weights, coin rewards or the halo cost. Pickup denominations are intentionally also whitelisted in the authority modules: changing the denominations requires updating those rules and tests, not merely a client label.

Edit `tools/world.py` to move floor pieces, signs, cells or spawn pads consistently, and `tools/theme.py` for palette, materials, lighting and lights. `WorldData.luau` and `ArtDirection.luau` are generated and should not be hand-edited; `tools/preview.py` re-renders the review plates from the same tables. The recommended published capacity is **8**, matching the safe spawn positions. The logical rules are additionally stress-simulated with 12 players; that is not a capacity/performance certification.

## Validation boundaries

`tools/check.py` compiles all Luau, strictly analyzes the pure authority/config modules, executes the core suite, and executes production adapters against `tests/roblox_mock.luau`. That mock provides explicit service boundaries and checks property/enum names against `tests/fixtures/roblox-api.json`, pinned to a Roblox API snapshot. It does **not** implement physics, actual networking, rendering, touch input or sound playback.

`tools/verify_place.py` checks embedded source, instance references, API property loadability, geometry support/spacing, bridge continuity, materials/shadows/lights, budget and the fast/standard variants. `tools/artcheck.py` checks the design rules (saturation ceilings, hierarchy order, purple/cyan restriction, lighting values, cell-vs-floor contrast, signage contrast) and freezes the collidable geometry, pickups and spawns against `tests/fixtures/world-baseline.json`. Builds are deterministic; exports must match the source. The GitHub workflow can repeat the same checks, but it has not been executed remotely in this session.

Always perform the short [Studio acceptance pass](TESTING.md) before treating the prototype as playtested or publishing it.
