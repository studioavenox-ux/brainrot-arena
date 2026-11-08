# BRAINROT ARENA — prototype build report

Verified: **2026-11-08T14:47:11+00:00**.

**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**
This Linux workspace has no Roblox Studio installation or Roblox control connector.

## Delivered

- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.
- Redesigned tropical lobby/arena: 824 anchored parts (831 instances incl. 7 baked sign
  boards), four connected satellite platforms, and 48 collectible slots.
- 12-second intermission → 180-second round → 9-second results; repeat automatically.
- Atomic server pickups (+1/+5/+10), synchronized HUD/leaderboard, late joins, respawns and fall rescue.
- Low gravity at 60 seconds for 25 seconds, then normal gravity; clean event/round resets.
- Winner/tie/no-score announcements; session coins; one server-validated session cosmetic.
- Server-authoritative arena access: heartbeat routing with verified pivots, backoff and a
  seated/dead-safe fallback, so a round always pulls every eligible player in and returns
  them afterwards. See [PHASE3_GAMEPLAY_FIXES.md](PHASE3_GAMEPLAY_FIXES.md).
- Complete game UI on a generated design system: top HUD (cells, coins, synchronized clock),
  live leaderboard, centre notifications (phase, chaos event, winner/tie), bottom Shop/Gear/
  Settings cards acting on real server data, lobby countdown; responsive from phone to
  desktop with reduced-motion and SFX preferences. See
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

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (includes 100 × 12-player logical round simulations) | 90 passed |
| Real server/client scripts against mocked Roblox services | 60 passed |
| XML/API/geometry export tests | 36 passed |
| Art-direction gate (palette, hierarchy, legibility, lighting) | 35 passed |
| Official Luau compilation | 24 files passed |
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
Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).
No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.

## Deliberate limits

- Coins/halo are session-only, not saved between server visits.
- One map and one event; no pets, additional maps, monetization, or persistent economy.
- Movement checks are a basic sanity layer, not a complete exploit-prevention system.
- Bundled pickup tone availability and exact visual polish still need the Studio/device pass.

## Export integrity

Source SHA-256: `07d49691281e354da80ccbed6c85e008cb1a84038e9c515146d063545fdaaab5`

- `BrainrotArena-QuickTest.rbxlx` — 1,603,336 bytes; SHA-256 `92595a0cb39ac424e00218039f6bade64e969efc8360fcd288ac5cadc8ad3f4d`
- `BrainrotArena.rbxlx` — 1,603,337 bytes; SHA-256 `c724dde201b9bb32f76917e2dfa22f7428a36a554185cff7de7758070fb94953`
