# The unavoidable Studio acceptance pass

**Not yet performed:** this development environment is Linux without Roblox Studio or a Roblox control connector.
The full Phase 5 matrix (20 rows: stealing, protection, stages, all five events, persistence,
UI scaling) lives in [TEST_REPORT_PHASE5.md](TEST_REPORT_PHASE5.md). Automated checks are
kept strictly separate from that matrix: 321 automated tests pass in the current gate (the live count is in the [build report](BUILD_REPORT.md)), and none of them is a
substitute for a Studio run. The matrix's "five events" rows describe the superseded schedule; the current event rules are in [CHAOS_EVENTS.md](CHAOS_EVENTS.md). The included Luau logic, adapter contracts, generated map and place structure were checked locally; only Roblox Studio can verify real character physics, rendering, audio and client/server replication.

## Fastest beginner test

1. On Windows, right-click the downloaded ZIP → **Extract All…**, then open the extracted `BrainrotArena` folder. Start Roblox Studio, sign in, and choose **File → Open from File…** → **`places\BrainrotArena-QuickTest.rbxlx`**. No script pasting, plugins, asset imports or publishing is required.
2. In the playtest-mode dropdown next to Studio's top **Play** button, choose **Server & Clients**, set **2 clients**, then click **Play** or press **F7** (**Fn+F7** on some laptops). One server session and two client sessions open. In older ribbon layouts, these controls are under **Test → Server & Clients / Local Server**; select **2 players**, then **Start**.
3. Use both **client** windows to walk into glowing cells. The server window is for inspection. Watch one complete cycle and check the items below. Click **End Session** to stop the local server and clients. The root [Windows README](../README.md) includes complete extraction, solo playtest, multiplayer and dependency instructions.

| Stage | Standard place | QuickTest (Studio only) |
|---|---:|---:|
| Intermission | 12 seconds | 4 seconds |
| Active round | **180 seconds** | 50 seconds |
| Chaos Event start / duration | 105 s / 35 s (one random kind) | 8 s / 35 s (one random kind) |
| Stage boundaries | Collect 0 / Compete 45 / Chaos 105 / Final 150 | 0 / 8 / 18 / 24 |
| Results | 9 seconds | 5 seconds |

QuickTest is gated by `RunService:IsStudio()`. Even if that place is accidentally published, the server uses standard timings outside Studio. Use the standard place for normal play and any publishing.

## Arena access — the Phase 3 fix, and how to confirm it

Routing is server-authoritative (`src/server/core/ArenaRoute.luau` + the mover in
`Main.server.luau`). It runs on every heartbeat, not on a phase-change event.

- [ ] **Intermission → round.** Both players start on the lobby deck. When the clock
      hits zero, *both* are moved to different arena pads. Nothing about the portal
      needs to be touched; walking through it is optional.
- [ ] **Seated player.** Sit on a lobby bench during the intermission. The round
      must still pull you in. (This is the case a single unverified `PivotTo` used to
      silently lose; the server now detects the refusal and falls back.)
- [ ] **No ping-pong.** Stand on the causeway mid-round: you must not be yanked back
      and forth between lobby and arena. The causeway counts as arrived for both.
- [ ] **Respawn and fall.** Reset character mid-round, or fall off an island: you
      return to the arena with your score. A dead avatar is never force-teleported;
      it is re-routed on respawn.
- [ ] **Late join.** Join a second client mid-round: that player is routed in on the
      next heartbeat and appears on both leaderboards with 0 cells.
- [ ] **Round end.** At the deadline every player returns to the lobby and the results
      card shows. A player who joins during `Results` stays in the lobby.
- [ ] **Output window.** No `[Brainrot] route fallback` lines in a normal session. If
      one appears, it names the player and destination — that is the fallback doing
      its job, and it is worth reporting with the reproduction.

## Acceptance checklist — currently pending in Studio

### Interface (Phase 3)

- [ ] Top HUD: brain-cell counter (left), round clock (centre, counting down from the
      server's `phaseEndsAt`), coin counter (right). All three match the server.
- [ ] Leaderboard on the right lists every player ordered by cells, marks your own
      row, and moves rows as scores change. **Tab** toggles it.
- [ ] **Shop** opens the halo stand with your real balance; buying deducts exactly 100
      coins and equips the halo; with fewer coins the server replies "Not enough
      session coins" and nothing is charged.
- [ ] **Gear** (inventory) shows your real round score, wins, cells claimed and coin
      balance; **Settings** toggles SFX and reduced motion locally. **H** / the `?`
      chip opens how-to-play, **Esc** closes any card.
- [ ] Lobby panel: welcome copy, phase word and the next-round countdown while you are
      waiting; it disappears when the round starts.
- [ ] Low gravity raises a centre banner with a live countdown; it clears when the
      event ends. A pickup by another player raises a toast.
- [ ] Device Emulator, small phone portrait **and** landscape: nothing overlaps the
      clock, the coin counter, the **SPECIMENS** chip or the **RANKS** chip (they form
      one right-hand stack; the toast band starts below all of them on portrait and
      in the gap between the cell chip and the stack on landscape), the action bar
      clears the thumbstick/jump zones, the leaderboard starts collapsed behind
      **RANKS**, and every card fits the screen.
- [ ] iPad/tablet and 1280×720 desktop: brand lockup and rarity key appear, action bar
      hugs the bottom edge.

### Gameplay

- [ ] Both players spawn in the lobby, see the same phase/countdown and automatically arrive at different arena spawn pads.
- [ ] Collecting pink/gold/prismatic cells adds exactly **1/5/10**, respectively. Both clients' leaderboards update.
- [ ] Walk both players into the **same** cell: only one receives that generation's reward. It returns about five seconds later.
- [ ] In QuickTest, the **INCOMING** banner appears at 5 seconds and the **CHAOS EVENT** banner at 8 seconds, on both clients. The countdown reaches zero at 43 seconds. Repeat until you have seen each kind once: LOW GRAVITY (floaty jumps), BOUNCY WORLD (higher jumps), SLIPPERY CHAOS (sliding), BRAIN CELL RUSH (more Rare and Prismatic cells). Normal play must return with no leftover effect.
- [ ] During SLIPPERY CHAOS, respawn a player (Reset Character) and have them walk on the floor. They should slide like everyone else.
- [ ] Use Roblox's **Reset Character** during play. After respawn, the player is back in the arena and retains the round score. Jump/fall off an island and confirm rescue also preserves points.
- [ ] At the deadline, cells disappear, both players return to the lobby, the correct winner/tie/no-score card appears, and coins are paid once. The following round resets scores and respawns all cells.
- [ ] In Studio's **Device Emulator**, check a small phone in portrait and landscape: timer, RANKS toggle, help and the action bar remain readable; joystick/jump remain usable.
- [ ] Check Studio **Output** for red errors. Confirm the bundled pickup chime plays, the SFX toggle mutes it, and reduced motion stops cell bobbing/spinning/sparks. Sound availability can vary with Roblox's installed bundle.
- [ ] Music: `Config.Audio` ships with **no sound IDs**, so the game is silent by default. Expect silence until you configure IDs as described in [AUDIO.md](AUDIO.md). Once configured, check that the lobby, arena and Chaos tracks crossfade, that the round and Chaos stingers play on their edges and not on join, and that the Settings **Sound and music** toggle silences everything.

### Visual acceptance (added with the art-direction redesign)

- [ ] At the spawn pad, look toward the gate: the **BRAINROT / ARENA** wordmark, the hanging **SYNAPSE CIRCUIT** banner and both side boards are legible without walking closer.
- [ ] Walk lobby → gate → arena: sand and stone read as one continuous natural palette; no neon cyan floor, lime foliage or purple platform remains.
- [ ] Stand at arena centre height and identify **pink, gold and prism** cells by both colour *and* silhouette (halo / crown / crossed arms), including at the lowest graphics quality.
- [ ] Low gravity triggers: beacon ring, gate rails and the HUD pulse prismatic; the environment stays natural (no full-screen colour wash).
- [ ] Confirm `Lighting` contains `TropicalDaySky`, `CoastalHaze`, `GameplayBloom`, `NeutralGrade` and exactly **7** PointLights, all with `Shadows` off.
- [ ] Device Emulator: the scene still reads clearly on a small phone and frame rate stays acceptable on Studio's "lowest" graphics quality.

Optional edge checks: start another client mid-round; disconnect the current leader; let all players leave during low gravity; rejoin and confirm the server returns to intermission with normal gravity. A zero-score round must not invent a winner. Shared first place pays the winner bonus to each tied player.

## Testing session rewards

Each round pays `10 + 2 × score`, plus `30` to every winner with a positive score. In the **Shop**, buy the 100-coin Pulse Halo using earned coins. Verify its balance deduction, equip/unequip, and appearance after respawn. Coins/ownership intentionally reset on leaving the server; no DataStore or Studio API-service setting is needed.

## What was already run here

- Official Luau compilation of all production scripts and test files.
- Strict analysis of the pure server authority modules, `ChaosRules`, `AudioRules` and shared configuration.
- **145 core tests**, including the character rules (switch quota, Chaos-only bonus, per-character cooldowns that survive switching, round reset), ability geometry and slow statuses, grants to the movement guard, and the QuickTest and normal event timing, the Chaos pool, audio rules (track choice, fade timing, ID validation, cue lookup, no invented IDs), and 100 logical 12-player rounds, tie payouts, generation/replay protection, invalid inputs, empty-server recovery, movement sanity and the routing policy (zones, transit neutrality, backoff, escalation, give-up).
- **105 adapter tests** executing the actual server/client/HUD/effect scripts against **mocked** Roblox services, with API/enum names checked against a pinned Roblox API fixture — including the Chaos director (gravity, friction restore, friction on spawned and respawned characters, watcher cleanup, write-once friction), a live-server Slippery test for respawns and late joins, a 35-second lifecycle measurement, Bouncy World and Slippery floor wiring, the audio controller (crossfade, mute, cleanup, no stinger on join), 13 live routing scenarios (seated refusal, mid-round join, fall rescue, respawn, no-loop, player leave), the whole interface (responsiveness at six viewports, live leaderboard ordering, shop/inventory/settings acting on real state, keyboard shortcuts, event banner, results card) plus lighting, materials and the cell-visual part budget. The character and ability tests cover: remote argument validation; switch quotas and the Chaos-only bonus end to end; every ability's effect (knockback, dash, launch, slows, decoy) and its exact targeting; server cooldown refusal and persistence across switches; no Brain Cell change; the name tag; and the Q key, digit keys and button wiring; respawn clearing slows.
- **36 export tests** checking embedded source/hierarchy, supported property names, spawn/floor geometry, materials, shadows, point lights, sign fonts, part budget, bridge continuity and both place variants.
- **35 art-direction tests** covering palette ceilings, hierarchy order, purple/cyan restriction, lighting values, post-processing limits, cell-vs-floor contrast, signage contrast, the frozen walkable geometry, and the HUD design system (WCAG pairs incl. panels composited over sunlit sand, accent hue separation, no hardcoded colours or raw buttons, generated theme in sync). Plus `docs/previews/` renders from `tools/preview.py` (world) and `tools/uidraw.py` (interface) — software renders, not engine screenshots.
- Deterministic rebuild and whitespace checks.

These tests do **not** prove Studio import, physics/collision behaviour, real network replication, rendered text fit, rendered lighting/materials, audible music or cue playback, or real-device touch behaviour. See the current [build report](BUILD_REPORT.md) for exact execution status.

## If something fails

Send the red Output message, which place you opened, and the failed checklist item. Do not manually paste replacement scripts into many locations. Fix the source once, run `python3 tools/build_place.py`, and reopen the rebuilt place. Stop a running test before opening the other place; opening a project while a simulation is running can be confusing.

## Optional publishing

Publishing was **not** attempted. Once the checklist passes, use Studio's normal publish flow under your account and set the server capacity to **8** (matching the eight spawn pads). Test an actual private server before a public release. No monetization is included or needed.
