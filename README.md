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

- **One original lobby + Synapse Circuit arena:** 824 anchored map parts in a natural tropical art direction — pale sand and teal stone courts, a tea pavilion, lookout tower, beach bar and shore shrine on the arena promenade, a kiosk/pergola/terrace lobby, a warm-lit gate, one brain beacon and an ocean horizon — plus four bridged satellite platforms, each with its own landmark. [Phase 1 report →](docs/VISUAL_CHANGES.md) · [Phase 2 report →](docs/VISUAL_CHANGES_PHASE2.md)
- **Six original characters as real 3D Models:** **BRAINY** the brain and **BLORBO** the frog (+1),
  **GLORP** the fish and **HJONK** the goose (+5), **CRUSTY** the toast and **WHIFFERS** the sock
  (+10). Each is a separate, named, low-poly Model built from primitives — no image, no uploaded
  mesh — with a face, its own proportions, idle and collect motion, a floating name + rarity card
  and a pickup burst. All six are baked into the places under `Workspace → BrainrotCharacters`
  (each on a plinth in the lobby exhibit) *and* instantiated in the arena. The server rolls the
  species and the reward; the client can only animate the receipt.
  [Phase 4 report →](docs/CHARACTERS_PHASE4.md)
- **Phase 5:** stealing, staged rounds, five survival events and persistent profiles.
  [Phase 5 report →](docs/PHASE5_STEAL_AND_EVENTS.md) · [Test report →](docs/TEST_REPORT_PHASE5.md)

### 5. The steal, in one paragraph

Carried cells are at risk between stage boundaries; banked cells never are. Stand within
13 studs of a rival and press **E** or tap **STEAL**. The server finds the nearest eligible
rival, refuses if you are on cooldown, if they just spawned, if they were robbed in the last
four seconds or if you robbed *them* in the last twelve, takes their largest carried cell and
puts it in your carried pile — where it can be taken back. Every refusal has its own message
(`PROTECTED`, `TOO FAR`, `NOTHING TO TAKE`, `RECHARGING`, `SAME TARGET`), and the button's cooldown
is driven by the server's own timestamp.
- **Specimen log:** a collection screen of six live 3D viewports showing name, rarity, reward,
  catch count and whether the character has been seen. Uncaught entries render as silhouettes
  reading `NOT SEEN YET`. Open it with the gear card, the `SPECIMENS n / 6` chip or **C**.
- **Staged 3-minute rounds:** waiting → 12s intermission → **180s round** split into
  **Collect → Compete → Chaos → Final Rush** → 9s results → repeat. Every stage boundary
  **banks** what you are carrying; what is banked can never be lost. Solo testing also works,
  and late joiners enter the active round at zero.
- **Stealing:** a short-range tag (**E** or the on-screen **STEAL** button) that moves **one
  carried cell** from the nearest rival to you. 8s cooldown, 3s spawn protection, 4s victim
  immunity and a 12s no-repeat window, all validated on the server from server positions.
  Banked score is never at risk and nothing leaves the round — it only changes hands.
- **Five survival events:** low gravity, slippery stone, three orbiting rafts (real geometry,
  server-moved), collectible rush and four vanishing paths. Each is announced **6 seconds
  ahead** in an amber `INCOMING` banner, then runs with a live countdown, then resets itself.
- **48 server-controlled Brain Cell slots:** pink **+1**, gold **+5**, prismatic **+10**
  (displayed as Common / Rare / Legendary); five-second respawns. Atomic claiming prevents
  double rewards, and each cell resolves to one specific character.
- **Event schedule:** low gravity at 60s for 25s, then a wildcard at 108s for 18s — rotated
  deterministically by round number, so consecutive rounds differ and every client agrees.
- **Complete game UI:** a top HUD (brain cells, coins, synchronized round clock), a live server-driven leaderboard, centre notifications (round flow, chaos events, winner/tie), a bottom bar with **Shop**, **Gear** and **Settings**, and a lobby panel with the next-round countdown. Dark navy translucent panels, cyan/violet/amber accents, rounded corners and short tweens; it reflows for desktop, tablet and phone in both orientations.
- **Recovery:** death/reset rejoins the current arena; falling rescues the player without losing points; round cleanup removes cells and resets gravity.
- **Persistent progression:** 10 coins for participation + 2 per point + 30 for each tied
  winner. Coins, the specimen log, lifetime stats (rounds, wins, best score, steals, losses),
  and the original Pulse Halo (100 coins) are saved server-side in a DataStore with
  schema-checked, retried, pcall-protected reads and writes — and a documented memory
  fallback if storage is unavailable. No Robux, no monetization, no pay-to-win.
- **Server boundaries:** no score-submission remote; server-only positions, values, eligibility, payout, prices, and ownership. Requests use three small rate-limited argument-free verbs: `Snapshot`, `Halo` and `Steal`.

Coins, the specimen log, lifetime stats and the halo now persist across sessions. Extra maps,
pets, custom character packs, emotes and monetization are deliberately outside this release; see
[KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) for the full list, including the pending
Roblox Studio acceptance pass.

### Controls

Use Roblox's normal **WASD / Space / mouse** controls on desktop or the default **thumbstick / jump** controls on mobile. Walk into cells; no pickup button is required. **E** steals, **Tab** toggles the leaderboard, **H** opens the how-to card, **B** opens the shop, **C** opens the specimen log, **Esc** closes a card. Every one of those also has an on-screen button. On phones the action bar sits above the thumbstick and jump zones, and the leaderboard collapses behind **RANKS** so it never covers the round clock.

## Included files

```text
places/                     Ready-to-open standard and QuickTest places
src/server/Main.server.luau  Roblox server adapter / authoritative gameplay loop
src/server/core/             Strict, engine-independent round/pickup/movement rules
src/server/WorldService.luau  Reuses baked map; builds the same map for Rojo users
src/server/ArtService.luau    Applies the shared lighting rig (idempotent)
src/shared/ArtDirection.luau  Generated palette/lighting mirror of tools/theme.py
src/server/WorldData.luau     Generated runtime geometry and spawn data
src/shared/Config.luau       Timings, physics, rarity, coin and cosmetic settings
src/client/                 HUD (HUD, Panels, Kit, generated Theme), character Models, specimen log, silhouettes, cell FX, preferences
tests/                      Core tests + production-script contract tests + API fixture
tools/                      Deterministic place build, verification, art checks, previews and packaging
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

The test suite executes 90 core Luau tests (including 100 simulated 12-player logical rounds), 60 production-adapter tests against explicit Roblox service doubles, 36 XML/API/geometry tests and 35 art-direction tests — 221 in total. **Mocks are not Roblox Studio or a real multi-client network.** A GitHub Actions workflow is provided; it has not been run on GitHub from this sandbox.
