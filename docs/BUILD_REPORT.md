# BRAINROT ARENA — prototype build report

Verified: **2026-11-08T12:57:07+00:00**.

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
- Responsive HUD with touch-control clearance, SFX toggle and reduced-motion setting.
- Visual redesign: natural sand/teal/stone palette, tropical greens, soft blue sky with a
  warm 15:20 sun, authored materials and shadows, redesigned gate/signage, rarity
  silhouettes. Gameplay rules and walkable geometry are unchanged. See
  [VISUAL_CHANGES.md](VISUAL_CHANGES.md) and the renders in `docs/previews/`.

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (includes 100 × 12-player logical round simulations) | 72 passed |
| Real server/client scripts against mocked Roblox services | 32 passed |
| XML/API/geometry export tests | 30 passed |
| Art-direction gate (palette, hierarchy, legibility, lighting) | 30 passed |
| Official Luau compilation | 18 files passed |
| Strict analysis | 3 authority modules + Config passed |
| Repeat build | Byte-for-byte deterministic |
| Git whitespace check | Passed |

The headless adapter tests validate code contracts, not Roblox physics, actual networking, UI rendering, or audio.
`docs/previews/*.jpg` are software renders of the same geometry/colour tables (tools/preview.py),
not engine captures; rendered lighting and materials still need the Studio pass.

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

Source SHA-256: `440ea4f6b66c482fb56d5c646663d7ef3235c0a352db90cc127e1b91b7c40d98`

- `BrainrotArena-QuickTest.rbxlx` — 1,411,092 bytes; SHA-256 `148af6f7a6e1ae48a077e2c883cf6db6840d522097a1bca6f81b634139b7e245`
- `BrainrotArena.rbxlx` — 1,411,093 bytes; SHA-256 `5ad8a3c05c32180f14bc1a556a91a5889b4874dc435a46c60b9748d661ea95e9`
