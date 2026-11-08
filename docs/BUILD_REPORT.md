# BRAINROT ARENA — prototype build report

Verified: **2026-11-08T14:06:05+00:00**.

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

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (includes 100 × 12-player logical round simulations) | 82 passed |
| Real server/client scripts against mocked Roblox services | 52 passed |
| XML/API/geometry export tests | 30 passed |
| Art-direction gate (palette, hierarchy, legibility, lighting) | 34 passed |
| Official Luau compilation | 22 files passed |
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
Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).
No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.

## Deliberate limits

- Coins/halo are session-only, not saved between server visits.
- One map and one event; no pets, additional maps, monetization, or persistent economy.
- Movement checks are a basic sanity layer, not a complete exploit-prevention system.
- Bundled pickup tone availability and exact visual polish still need the Studio/device pass.

## Export integrity

Source SHA-256: `21cf89e603bac8b0aacc5a2917b28ee10ab2a2aaff7abc479fb0e616f752b8e7`

- `BrainrotArena-QuickTest.rbxlx` — 1,449,193 bytes; SHA-256 `a03ac5752357d2b35710ca0b641594d5bd5cb27526dfd5015b0f7015cc37adf8`
- `BrainrotArena.rbxlx` — 1,449,194 bytes; SHA-256 `05f1666fa33a0225eaca149dbcb36fd9405304961a28cdd5370b51d47a825b1c`
