# BRAINROT ARENA — prototype build report

Verified: **2026-11-09T10:40:08+00:00**.

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
- **One Chaos Event per round**, exactly 35 s, drawn server-side from four kinds (Low Gravity,
  Bouncy World, Slippery Chaos, Brain Cell Rush) that never overlap another event. It opens at
  105 s in the normal round (6 s warning) and at 8 s in QuickTest (50 s round, 3 s warning). Each
  kind is cleaned up at 35 s. See [CHAOS_EVENTS.md](CHAOS_EVENTS.md).
- **Dynamic audio** (configured, silent by default): lobby, arena and Chaos music that crossfade,
  round and Chaos stingers, one Sound setting, and an ability-cue API. No sound IDs are bundled.
  See [AUDIO.md](AUDIO.md).
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
- **Character selection and abilities:** the six characters are free and playable. One is active at a
  time. Each player gets 3 normal switches per round, plus 1 bonus switch during the Chaos Event (four
  at most). Each character has its own server-side cooldown that survives switching and resets at the
  next round. Abilities are BRAINY Mind Trick (decoy), BLORBO Belly Bounce (knockback), GLORP Bubble Dash
  (burst), HJONK HONK Wave (slow area), CRUSTY Toast Launch (upward launch) and WHIFFERS Sock Snare (slow).
  The Ability and Character remotes are separate and validated on the server. Abilities never award,
  steal or move Brain Cells. Mobile button and PC key Q, with 1–6 for switching. See
  [PHASE_CHARACTERS_ABILITIES.md](PHASE_CHARACTERS_ABILITIES.md).
- Event-only raft and path geometry from earlier builds stays in the export, inert at rest
  (non-colliding), and is no longer scheduled. Rendered previews: `docs/previews/events.jpg`
  (three orbit rafts and four vanishing spans, drawn at rest, non-colliding).

## Checks actually executed

| Check | Result |
|---|---:|
| Luau core tests (100 × 12-player round simulations + steal / stage / event rules) | 145 passed |
| Real server/client scripts against mocked Roblox services (+ steal, persistence, characters and abilities) | 103 passed |
| XML/API/geometry export tests | 36 passed |
| Art-direction gate (palette, hierarchy, legibility, lighting) | 35 passed |
| Official Luau compilation | 32 files passed |
| Strict analysis | authority modules (incl. CharacterRules and AbilityRules), ChaosRules, AudioRules and Config passed |
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

Characters: switch with the buttons and keys 1–6, fire each ability (Q or the button) with two clients,
confirm the knockback, dash, launch, slow and decoy look right, and confirm a Chaos switch works once.

Phase 5 adds a hands-on pass that cannot be automated: stand two clients within 13 studs and
tap **STEAL** (one carried cell should change hands and both clients should be told), press it
again to see the 8-second refusal, tag a freshly respawned player to see `PROTECTED`, watch a
stage boundary bank the carried cells, and watch the Chaos Event warn, run for 35 s and clean up. The full
20-row matrix is in [TEST_REPORT_PHASE5.md](TEST_REPORT_PHASE5.md).

Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).
No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.

## Deliberate limits

- One map. The Chaos kind is drawn at random once per round from a pool of four.
- Stealing auto-targets the nearest eligible rival; there is no target picker (one tap on a phone).
- No cross-server session locking on profiles: two servers writing one player at the same moment
  resolve last-write-wins. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
- Movement checks are a basic sanity layer, not a complete exploit-prevention system.
- Bundled pickup tone availability, music and cue playback (no sound IDs are configured yet) and exact visual polish still need the Studio/device pass.

## Feature status (final verification pass)

**Completed and covered by automated tests**

- Chaos Events: exactly one 35 s event per round, drawn server-side from Low Gravity, Bouncy World,
  Slippery Chaos and Brain Cell Rush; never overlapping; the window is cleared at 35 s.
  Event timing: production 180 s round, event at 105 s, 6 s warning; QuickTest 50 s round, event at 8 s,
  3 s warning. Both are asserted explicitly.
- Event lifecycle: the server applies each edge on the first 0.1 s authority step at or after its
  scheduled time, so the window lasts exactly 35 s. Gravity, friction, jump power and rarity all
  return to normal at the end. An adapter test measures this in 10 ms steps.
- Slippery Chaos reaches newly spawned, respawned and late-joining characters through the live server flow.
  Friction is removed from every part when the window closes. A mutation check disabling the watcher
  fails these tests.
- Dynamic audio logic: track choice, crossfade timing, stingers on edges only, mute, cleanup, and
  validation of configured IDs. Every sound ID ships empty, so the game is silent until IDs are set.
- Server authority, stealing, stages, persistence, routing, UI logic, and export integrity (see above).

**Incomplete (not started)**

- Pets (60-pet collection, active slots, inventory), eggs and hatch timers, Spin the Wheel.
- Robux-only secret characters and pets, MarketplaceService purchases and receipt validation.
- Ability sound cues: the cue API exists and abilities are wired to it, but no ability sound IDs are set.
- Steal sound cue: configured but not wired to the steal path.
- Music and sound asset IDs: none configured.
- Third-person camera and animations, the expanded HUD and settings for the later phases.

**Unverified (automated checks only; no Roblox run)**

- Roblox Studio import and the real engine's physics (Chaos feel: gravity, bounce, slipperiness).
- Real network replication and a multi-client session. The mock simulates two players only.
- Audible music, cues, and crossfades.
- Touch input, layout, and text on real phones. Android frame rate against the 60 FPS target.
- DataStore behaviour on the live service. Published-server behaviour.
- Renders in `docs/previews/` are software renders, not engine captures.

## Remaining Studio testing requirements

1. Open `places/BrainrotArena-QuickTest.rbxlx`, start 2 clients, and confirm no red Output errors.
2. Watch the event sequence in QuickTest: INCOMING at 5 s, CHAOS EVENT at 8 s, end at 43 s. Check that each
   kind shows its effect, and that normal play returns afterwards with no leftover effect.
3. During Slippery Chaos, reset a character and join a third client: they must slide like everyone else.
4. Confirm the full round (both clients): collect, steal, stage banks, results, and next round.
5. Confirm the Sound and music toggle mutes everything, and that stingers do not fire on join.
6. Check touch controls, text fit and frame rate in Device Emulator and on an Android device (not run).
7. Only after the above passes: publish to a private server and run the same checks there.

## Export integrity

Source SHA-256: `ac0f0647d4dbb3dd52e4cbe68db9b019f5459a8fa959022175c91d8ab65e5ef8`

- `BrainrotArena-QuickTest.rbxlx` — 1,833,278 bytes; SHA-256 `e7b0001eb5157e7684d71a8acbf25bd0b93457316439f942b6530fe03012b5bc`
- `BrainrotArena.rbxlx` — 1,833,279 bytes; SHA-256 `fe818bcc969760b8a34a34cf9660980348562d363170232994838648bded4814`
