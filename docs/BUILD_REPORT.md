# BRAINROT ARENA — prototype build report

Verified: **2026-10-28T10:35:00+00:00**.

**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**
This Linux workspace has no Roblox Studio installation or Roblox control connector.

## Delivered

- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.
- Original 358-part lobby/arena, four connected satellite platforms, and 48 collectible slots.
- 12-second intermission → 180-second round → 9-second results; repeat automatically.
- Atomic server pickups (+1/+5/+10), synchronized HUD/leaderboard, late joins, respawns and fall rescue.
- Low gravity at 60 seconds for 25 seconds, then normal gravity; clean event/round resets.
- Winner/tie/no-score announcements; session coins; one server-validated session cosmetic.
- Responsive HUD with touch-control clearance, SFX toggle and reduced-motion setting.

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (includes 100 × 12-player logical round simulations) | 72 passed |
| Real server/client scripts against mocked Roblox services | 29 passed |
| XML/API/geometry export tests | 28 passed |
| Official Luau compilation | 13 files passed |
| Strict analysis | 3 authority modules + Config passed |
| Repeat build | Byte-for-byte deterministic |
| Git whitespace check | Passed |

The headless adapter tests validate code contracts, not Roblox physics, actual networking, UI rendering, or audio.

## Remaining acceptance work

Open `places/BrainrotArena-QuickTest.rbxlx` in Roblox Studio and use its Test tab to start **2 clients**.
Confirm collecting, jumping during low gravity, the winner card, and the next round on both clients.
Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).
No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.

## Deliberate limits

- Coins/halo are session-only, not saved between server visits.
- One map and one event; no pets, additional maps, monetization, or persistent economy.
- Movement checks are a basic sanity layer, not a complete exploit-prevention system.
- Bundled pickup tone availability and exact visual polish still need the Studio/device pass.

## Export integrity

Source SHA-256: `a733440904169150e25e2abfebea4afc952843407763d7158491d71096a2dfdb`

- `BrainrotArena-QuickTest.rbxlx` — 634,417 bytes; SHA-256 `75d1da51d9da9ad9fd8221870a111ec534494ba314a094cffcaee9622dd353cf`
- `BrainrotArena.rbxlx` — 634,418 bytes; SHA-256 `004d966e102b739b22cf4f35e05555171177a01a61de9d05d8543ab5a6fc4520`
