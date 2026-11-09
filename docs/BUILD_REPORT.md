# BRAINROT ARENA — prototype build report

Verified: **2026-11-09T07:45:45+00:00**.

**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**
This Linux workspace has no Roblox Studio installation or Roblox control connector.

## Delivered

- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.
- Redesigned tropical lobby/arena: 906 anchored parts (824 map + 82 Phase 5 event parts;
  913 instances incl. 7 baked sign boards), four connected satellite platforms, and 48
  collectible slots.
- 12-second intermission → **180-second staged round** → 9-second results; repeat automatically.
  Stages: Collect 0 s / Compete 45 s / Chaos 105 s / Final Rush 150 s, each boundary banking
  every player's carried cells.
- Atomic server pickups (+1/+5/+10), synchronized HUD/leaderboard, late joins, respawns and fall rescue.
- **Stealing:** one argument-free `Steal` verb resolved entirely on the server — nearest rival
  within 13 studs, 8-second cooldown, 3-second spawn protection, 4-second victim immunity,
  12-second no-repeat window; moves one *carried* cell and never touches banked score.
- **Five survival events** with 6-second warnings and self-resetting state: low gravity (60 s,
  25 s), then a deterministic wildcard (108 s, 18 s) rotating slippery stone, three
  server-moved orbit rafts, collectible rush and four vanishing paths.
- Winner/tie/no-score announcements; **persistent** coins, specimen log, lifetime stats and the
  server-validated Pulse Halo in a DataStore profile with a documented memory fallback. See
  [PHASE5_STEAL_AND_EVENTS.md](PHASE5_STEAL_AND_EVENTS.md).
- Server-authoritative arena access: heartbeat routing with verified pivots, backoff and a
  seated/dead-safe fallback, so a round always pulls every eligible player in and returns
  them afterwards. See [PHASE3_GAMEPLAY_FIXES.md](PHASE3_GAMEPLAY_FIXES.md).
- Complete game UI on a generated design system: top HUD (cells, coins, synchronized clock),
  live leaderboard, centre notifications (phase, chaos event, winner/tie), bottom Shop/Gear/
  Settings cards acting on real server data, lobby countdown; responsive from phone to
  desktop with reduced-motion and SFX preferences. The phone top bar is derived rather
  than hard-coded (coin chip sized first, clock takes what is left, the specimen and
  RANKS chips stack under it, message bands take the corridor or stack below), so no
  two controls can collide on a 320 pt-wide screen. See
  [UI_IMPLEMENTATION_PHASE3.md](UI_IMPLEMENTATION_PHASE3.md) and `docs/previews/ui-*.jpg`.
- Visual redesign: natural sand/teal/stone palette, tropical greens, soft blue sky with a
  warm 15:20 sun, authored materials and shadows, redesigned gate/signage, rarity
  silhouettes. Gameplay rules and walkable geometry are unchanged. See
  [VISUAL_CHANGES.md](VISUAL_CHANGES.md) and the renders in `docs/previews/`.
- Six original characters as real, separate Roblox Models — BRAINY (brain, Common, +1),
  BLORBO (frog, Common, +1), GLORP (fish, Rare, +5), HJONK (goose, Rare, +5), CRUSTY
  (toast, Legendary, +10), WHIFFERS (sock, Legendary, +10) — procedurally built from
  primitives, baked into `Workspace.BrainrotCharacters` in both places as editable models
  on plinths with floating name/rarity cards, and instantiated at runtime for the 48 cells.
  Per-character idle and collect animation, pickup burst, and a collection screen of six
  live viewports. Server owns the species roll and the reward. See
  [CHARACTERS_PHASE4.md](CHARACTERS_PHASE4.md) and `docs/previews/cast.jpg`.
- Phase 5 event surfaces rendered from the same geometry table as the export:
  `docs/previews/events.jpg` (three orbit rafts with warm underglow, four vanishing
  spans with glow markers, both non-colliding at rest).

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (100 × 12-player round simulations + steal / stage / event rules) | 107 passed |
| Real server/client scripts against mocked Roblox services (+ steal and persistence) | 76 passed |
| XML/API/geometry export tests | 36 passed |
| Art-direction gate (palette, hierarchy, legibility, lighting) | 35 passed |
| Official Luau compilation | 26 files passed |
| Strict analysis | 3 authority modules + Config passed |
| Repeat build | Byte-for-byte deterministic |
| Git whitespace check | Passed |

The headless adapter tests validate code contracts, not Roblox physics, actual networking, UI rendering, or audio.
`docs/previews/*.jpg` are software renders of the same geometry/colour tables (tools/preview.py),
not engine captures; rendered lighting and materials still need the Studio pass.

## Remaining acceptance work

Open `places/BrainrotArena-QuickTest.rbxlx` in Roblox Studio and use its Test tab to start **2 clients**.
Confirm both players are pulled into the arena (including from a seated character), collecting,
jumping during low gravity, the winner card, the Shop purchase, and the next round on both clients.
Then walk the lobby exhibit (all six characters should be visible, named and animating), press
**C** to open the specimen log, catch one of each species, and confirm the log fills to 6 / 6

Phase 5 adds a hands-on pass that cannot be automated: stand two clients within 13 studs and
tap **STEAL** (one carried cell should change hands and both clients should be told), press it
again to see the 8-second refusal, tag a freshly respawned player to see `PROTECTED`, watch a
stage boundary bank the carried cells, and watch all five events warn, run and reset. The full
20-row matrix is in [TEST_REPORT_PHASE5.md](TEST_REPORT_PHASE5.md).

Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).
No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.

## Deliberate limits

- One map; wildcards rotate deterministically rather than being drawn at random.
- Stealing auto-targets the nearest eligible rival; there is no target picker (one tap on a phone).
- No cross-server session locking on profiles: two servers writing one player at the same moment
  resolve last-write-wins. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
- Movement checks are a basic sanity layer, not a complete exploit-prevention system.
- Bundled pickup tone availability and exact visual polish still need the Studio/device pass.

## Export integrity

Source SHA-256: `3dbd31d70d0bab8e0863837a0db904d250dd54badbadcaafd16ce94b558ed744`

- `BrainrotArena-QuickTest.rbxlx` — 1,791,117 bytes; SHA-256 `589d2927e6d83797efc39f0db09aa4c62096337c5068ba3c49b18908381dc29d`
- `BrainrotArena.rbxlx` — 1,791,118 bytes; SHA-256 `81f07df282224afdc21209eac2c67ee29bd009afe840d4cb54bd71e4563c9bdb`
