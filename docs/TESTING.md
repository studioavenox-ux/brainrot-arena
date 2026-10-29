# The unavoidable Studio acceptance pass

**Not yet performed:** this development environment is Linux without Roblox Studio or a Roblox control connector. The included Luau logic, adapter contracts, generated map and place structure were checked locally; only Roblox Studio can verify real character physics, rendering, audio and client/server replication.

## Fastest beginner test

1. On Windows, right-click the downloaded ZIP → **Extract All…**, then open the extracted `BrainrotArena` folder. Start Roblox Studio, sign in, and choose **File → Open from File…** → **`places\BrainrotArena-QuickTest.rbxlx`**. No script pasting, plugins, asset imports or publishing is required.
2. In the playtest-mode dropdown next to Studio's top **Play** button, choose **Server & Clients**, set **2 clients**, then click **Play** or press **F7** (**Fn+F7** on some laptops). One server session and two client sessions open. In older ribbon layouts, these controls are under **Test → Server & Clients / Local Server**; select **2 players**, then **Start**.
3. Use both **client** windows to walk into glowing cells. The server window is for inspection. Watch one complete cycle and check the items below. Click **End Session** to stop the local server and clients. The root [Windows README](../README.md) includes complete extraction, solo playtest, multiplayer and dependency instructions.

| Stage | Standard place | QuickTest (Studio only) |
|---|---:|---:|
| Intermission | 12 seconds | 4 seconds |
| Active round | **180 seconds** | 30 seconds |
| Low-gravity start | 60 seconds after round starts | 8 seconds after round starts |
| Low-gravity duration | 25 seconds | 10 seconds |
| Results | 9 seconds | 5 seconds |

QuickTest is gated by `RunService:IsStudio()`. Even if that place is accidentally published, the server uses standard timings outside Studio. Use the standard place for normal play and any publishing.

## Acceptance checklist — currently pending in Studio

- [ ] Both players spawn in the lobby, see the same phase/countdown and automatically arrive at different arena spawn pads.
- [ ] Collecting pink/gold/prismatic cells adds exactly **1/5/10**, respectively. Both clients' leaderboards update.
- [ ] Walk both players into the **same** cell: only one receives that generation's reward. It returns about five seconds later.
- [ ] At eight seconds into QuickTest, the low-gravity banner appears on both clients and jumps become floaty. Ten seconds later, normal gravity returns.
- [ ] Use Roblox's **Reset Character** during play. After respawn, the player is back in the arena and retains the round score. Jump/fall off an island and confirm rescue also preserves points.
- [ ] At the deadline, cells disappear, both players return to the lobby, the correct winner/tie/no-score card appears, and coins are paid once. The following round resets scores and respawns all cells.
- [ ] In Studio's **Device Emulator**, check a small phone in portrait and landscape: timer, ranks toggle, help, rewards and local score remain readable; joystick/jump remain usable. HUD controls have touch alternatives to keyboard shortcuts.
- [ ] Check Studio **Output** for red errors. Confirm the bundled pickup chime plays, the SFX toggle mutes it, and reduced motion stops cell bobbing/spinning/sparks. Sound availability can vary with Roblox's installed bundle.

Optional edge checks: start another client mid-round; disconnect the current leader; let all players leave during low gravity; rejoin and confirm the server returns to intermission with normal gravity. A zero-score round must not invent a winner. Shared first place pays the winner bonus to each tied player.

## Testing session rewards

Each round pays `10 + 2 × score`, plus `30` to every winner with a positive score. In **Rewards**, buy the 100-coin Pulse Halo using earned coins. Verify its balance deduction, equip/unequip, and appearance after respawn. Coins/ownership intentionally reset on leaving the server; no DataStore or Studio API-service setting is needed.

## What was already run here

- Official Luau compilation of all production scripts and test files.
- Strict analysis of the three pure server authority modules and shared configuration.
- **72 core tests**, including 100 logical 12-player rounds, tie payouts, generation/replay protection, invalid inputs, empty-server recovery and movement sanity checks.
- **29 adapter tests** executing the actual server/client/HUD/effect scripts against **mocked** Roblox services, with API/enum names checked against a pinned Roblox API fixture.
- **28 export tests** checking embedded source/hierarchy, supported property names, spawn/floor geometry, part budget, bridge continuity and both place variants.
- Deterministic rebuild and whitespace checks.

These tests do **not** prove Studio import, physics/collision behavior, real network replication, rendered text fit, audio availability or real-device touch behavior. See the current [build report](BUILD_REPORT.md) for exact execution status.

## If something fails

Send the red Output message, which place you opened, and the failed checklist item. Do not manually paste replacement scripts into many locations. Fix the source once, run `python3 tools/build_place.py`, and reopen the rebuilt place. Stop a running test before opening the other place; opening a project while a simulation is running can be confusing.

## Optional publishing

Publishing was **not** attempted. Once the checklist passes, use Studio's normal publish flow under your account and set the server capacity to **8** (matching the eight spawn pads). Test an actual private server before a public release. No monetization is included or needed.
