# BRAINROT ARENA

**An implemented Roblox party-game prototype, not a design-only brief.**
Original procedural floating islands, glowing Brain Cells, three-minute rounds, and a very unreasonable gravity problem.

> **Status:** Project files built; **129 automated tests passing**. Roblox Studio is not installed in the development sandbox, so actual Studio import, engine physics, multiplayer networking, device rendering, and sound playback have **not** been verified here. [Build report →](docs/BUILD_REPORT.md)

## Windows: extract, open and test

### 1. Requirements and extraction

1. Install the current **Roblox Studio for Windows** from [Roblox Creator Hub](https://create.roblox.com/) if it is not already installed. Launch Studio and sign in to your Roblox account. Use a supported Windows PC and an internet connection for Roblox installation/sign-in and normal platform resources.
2. Save **`BrainrotArena-Project.zip`** to your computer. In Windows File Explorer, right-click it → **Extract All…** → choose a writable folder → **Extract**. Do not open or edit the project directly inside the ZIP viewer.
3. Open the extracted **`BrainrotArena`** folder. It contains this `README.md`, a `places` folder, a `src` folder, an `assets` inventory, and `MANIFEST.json`. The manifest lists the packaged files and their SHA-256 checksums.

**No Python, Luau CLI, Rojo, plugins, paid assets, API keys, publishing or script pasting is needed to open or test the place in Studio.**

### 2. Open the normal three-minute game

1. In Roblox Studio, choose **File → Open from File…** (or press **Ctrl+O**).
2. Browse to the extracted folder and open **`BrainrotArena\places\BrainrotArena.rbxlx`**. If your file dialog filters it out, select **All Files**. Keep its `.rbxlx` extension; do not rename it to `.xml`, and do not insert it as a model into another place.
3. In the playtest-mode dropdown beside Studio's top **Play** button, select **Test**. Click **Play** or press **F5**. On a laptop whose function keys control hardware, use **Fn+F5**. Do **not** select **Run**: Run does not create a playable character.
4. Your character appears in the lobby. After **12 seconds**, the server automatically teleports players into the arena for a **180-second** round. Use **WASD** to move, **Space** to jump and the mouse to look around. Walk into Brain Cells to collect them; no interact/pickup key is needed.
5. Press **Shift+F5** or click **Stop** before opening a different place. Stopping restores the edit-time scene.

The place already contains the map and scripts. Opening `src` files individually is only for code editing, not for launching the game.

### 3. Exact two-player local multiplayer test

1. Stop any current playtest. Choose **File → Open from File…** and open **`BrainrotArena\places\BrainrotArena-QuickTest.rbxlx`**.
2. In the playtest-mode dropdown next to the top **Play** button, choose **Server & Clients**.
3. Set the **number of clients to 2** in the adjacent client-count control.
4. Click **Play** or press **F7** (**Fn+F7** on some laptops). Studio launches **one server session and two client sessions**. Wait for both clients to finish loading. This does not require two Roblox accounts or publishing the game.
5. In each **client** window, click inside the game viewport and move that player's character. The **server** window is for inspection, not player control. Confirm both clients see matching round state and leaderboard changes.
6. QuickTest uses **4 seconds intermission → 30 seconds play → 5 seconds results**. Low gravity begins **8 seconds into play**, lasts **10 seconds**, then restores normal gravity. Watch for the winner card and the next automatic round. A complete first intermission/play/results cycle is approximately **39 seconds**, excluding loading time.
7. Try collecting the same cell with both players: only one should receive that generation's points. Reset one avatar through Roblox's in-game menu and confirm its score is retained after respawn.
8. When finished, click **End Session** in any simulated session to close the simulated server and clients. On Studio versions with the older ribbon UI, the same controls are under **Test → Server & Clients / Local Server**: choose **2 players**, then **Start**. Do not use Team Test for this local check.

Open Studio's **Output** panel (under **Window**, or **View** in older layouts) to check for red errors. The more detailed [acceptance checklist](docs/TESTING.md) also covers touch layout, ties, fall rescue, sounds and repeated rounds. The current testing controls are documented in [Roblox's Studio testing modes guide](https://create.roblox.com/docs/studio/testing-modes).

QuickTest is fast **only inside Studio**; the existing implementation uses normal timings in published servers. Use the standard place for ordinary play and any future publishing.

### 4. Assets, dependencies and known limits

Both place files embed **all 10 gameplay Luau source files and the editable map**. Brain Cells, the halo, environment and UI are procedural/baked assets; their definitions are included. **No required project file or custom asset is missing.** No separate Toolbox model, texture pack, mesh, uploaded sound, external asset ID or package install is required.

Roblox Studio itself and Roblox's bundled **one pickup-tone file and six sky textures** are platform dependencies, not distributable project files. Their exact `rbxasset://` paths are listed in [assets/asset-manifest.json](assets/asset-manifest.json). Those bundled resources have **not** been verified in a Windows Studio installation here; unavailable resources can affect sound/sky appearance and must be checked in Studio. They are not silently replaced or omitted custom assets.

See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for the complete included/missing/dependency report. The prior 129-test automated verification report is retained unchanged; packaging does not imply a Windows or Roblox-engine playtest.

## Implemented

- **One original lobby + Synapse Circuit arena:** 358 anchored map parts, a brain beacon, signal palms, four bridged satellite platforms, and a readable yellow/cyan circuit.
- **Automatic multiplayer lifecycle:** waiting → 12s intermission → **180s round** → 9s results → repeat. Solo testing also works. Late joiners enter the active round at zero.
- **48 server-controlled Brain Cell slots:** pink **+1**, gold **+5**, prismatic **+10**; five-second respawns. Atomic claiming prevents double rewards.
- **Low gravity:** activates 60 seconds into each standard round for 25 seconds, with UI and lighting feedback, then restores normal gravity.
- **Responsive HUD:** synchronized clock, custom leaderboard, local score, coin balance, rarity key, help, winner/tie/no-score announcements, touch-friendly buttons, reduced motion, and SFX controls.
- **Recovery:** death/reset rejoins the current arena; falling rescues the player without losing points; round cleanup removes cells and resets gravity.
- **Session rewards:** 10 coins for participation + 2 per point + 30 for each tied winner. Earn 100 coins to unlock/equip the original Pulse Halo through **Rewards**. No Robux, no monetization.
- **Server boundaries:** no score-submission remote; server-only positions, values, eligibility, payout, prices, and ownership. Requests use two small rate-limited verbs.

**Coins and the halo last only for the current server session.** Persistent saves, extra maps/events, pets, custom character packs, and monetization are deliberately outside this release.

### Controls

Use Roblox's normal **WASD / Space / mouse** controls on desktop or the default **thumbstick / jump** controls on mobile. Walk into cells; no pickup button is required. **Tab** toggles ranks; **H** opens help. All HUD actions also have buttons. Mobile score panels leave room for the thumbstick and jump button.

## Included files

```text
places/                     Ready-to-open standard and QuickTest places
src/server/Main.server.luau  Roblox server adapter / authoritative gameplay loop
src/server/core/             Strict, engine-independent round/pickup/movement rules
src/server/WorldService.luau  Reuses baked map; builds the same map for Rojo users
src/server/WorldData.luau     Generated runtime geometry and spawn data
src/shared/Config.luau       Timings, physics, rarity, coin and cosmetic settings
src/client/                 HUD, local cell animation, pickup effects and preferences
tests/                      Core tests + production-script contract tests + API fixture
tools/                      Deterministic place build, verification and packaging
docs/                       Acceptance checklist, architecture and actual build report
default.project.json        Optional Rojo source workflow
```

## Optional developer workflow

**Not needed for Studio play.** With Python 3.10+ and official Luau CLI tools:

```sh
python3 tools/build_place.py  # rebuild both places after source/map edits
python3 tools/check.py        # rebuild + compile + analyze + execute + verify
python3 tools/package_release.py
```

On Linux/macOS with `make` and `g++`, `python3 tools/bootstrap_luau.py` builds pinned official **Luau 0.744** locally. Existing tools on `PATH` are also supported. [Architecture / editing notes →](docs/ARCHITECTURE.md)

The test suite executes 72 core Luau tests (including 100 simulated 12-player logical rounds), 29 production-adapter tests against explicit Roblox service doubles, and 28 XML/API/geometry tests. **Mocks are not Roblox Studio or a real multi-client network.** A GitHub Actions workflow is provided; it has not been run on GitHub from this sandbox.
