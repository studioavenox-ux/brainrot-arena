# BRAINROT ARENA — prototype build report

Verified: **2026-11-08T12:15:46+00:00**.

**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**
This Linux workspace has no Roblox Studio installation or Roblox control connector.

## Delivered

- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.
- Redesigned tropical lobby/arena: 588 anchored parts (601 instances incl. 13 baked sign
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
| Art-direction gate (palette, hierarchy, legibility, lighting) | 24 passed |
| Official Luau compilation | 16 files passed |
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

Source SHA-256: `2538c9bf8e68a943bd19c5dc20c5b13317fc1158005401baa87bbbaf3f0f2a1d`

- `BrainrotArena-QuickTest.rbxlx` — 1,023,162 bytes; SHA-256 `c424465aa3aa1cd883c83ebd1967c57791b4a13e20aefa45ce95aa045c1fcaad`
- `BrainrotArena.rbxlx` — 1,023,163 bytes; SHA-256 `60d5dd9dcb0b27475344d2232dd79d7ca5f90c027f605fb98ddb6c24f3186945`
