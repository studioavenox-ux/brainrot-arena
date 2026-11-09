# Studio check: custom UI does not appear in Play mode

Use this when the 3D lobby and default Roblox interface load, but the custom Brainrot UI (top HUD,
ability button, character strip) does not. It tells you exactly what to look at and what to send back.

## 1. Use the right file

This repository ships **`.rbxlx`** files (XML), not `.rbxl`:

- `places/BrainrotArena.rbxlx`: production place (180 s round).
- `places/BrainrotArena-QuickTest.rbxlx`: short test place (50 s round).

If the file you opened came from an older download or another folder, it may predate the character
UI. Re-download this branch and open the file from `places/`.

## 2. Play and read Output first

1. Open the place, then press **F5** (or Play).
2. Open **View → Output** and clear it.
3. Look for these lines, in this order. They are temporary startup diagnostics. Each line names the
   last step that ran:

   Server (from the `Script` in ServerScriptService):
   - `[Brainrot][server] script started`
   - `[Brainrot][server] remotes published`
   - `[Brainrot][server] modules required`
   - `[Brainrot][server] world ready`
   - `[Brainrot][server] persistence ready`

   Client (from the `LocalScript` in StarterPlayerScripts):
   - `[Brainrot][client] LocalScript started`
   - `[Brainrot][client] modules required`
   - `[Brainrot][client] waiting for BrainrotRemotes`
   - `[Brainrot][client] remotes found; building HUD`
   - `[Brainrot][client] HUD built`

   **The first line that is missing tells us where startup stopped.** For example, if the client prints
   `waiting for BrainrotRemotes` but never `remotes found`, the server did not publish the remotes; look for
   the red server error above it. If the client never prints `LocalScript started`, the LocalScript did not
   run at all.

4. Note every **red** error and every **yellow** warning, with its file and line.

## 3. What the player should see

If the client started correctly, you should see, in this order:

- A top bar with the brand and round/stage information, and the Brain Cell count.
- The lobby panel during intermission.
- Bottom right: the **ability** panel. Its caption reads `WAITING FOR PLAY` until a round starts,
  then `Q • READY`.
- A strip of six numbered character chips with a readout such as `BRAINY • 3 SWITCHES LEFT`.

## 4. If you see a red panel instead

A dark-red panel titled **BRAINROT ARENA UI DID NOT START** means the client detected the failure
itself. The panel text names the cause:

- *"The server did not publish BrainrotRemotes"*: the server script stopped before it could publish.
  The server's red error in Output is the cause.
- *"A server remote is missing"*: the server build is older than the client.
- *"The HUD failed to build"*: the client UI script raised an error. The message after the colon is the cause.

## 5. Checks inside Studio (during Play)

- **Explorer → Players → (your name) → PlayerGui**: a ScreenGui named **BrainrotHUD** should be present.
  Its `Enabled` property should be true, and `DisplayOrder` 10.
- **Explorer → ReplicatedStorage → BrainrotRemotes**: should contain `State`, `Pickup`, `Request`,
  `Ability`, `Character` and `CharacterState`. If the folder is missing, the server did not start.
- **Explorer → StarterPlayer → StarterPlayerScripts → BrainrotClient → Main**: a LocalScript.
  Its `Disabled` property should be false.

## 6. Test sequence once the UI shows

Run these with the production or QuickTest place, one client:

1. Lobby: the lobby panel is visible, and the top bar shows `0` Brain Cells.
2. Press **1–6** (or tap a chip): the readout changes to the matching character and the switch count drops
   by one. The name tag over your head changes.
3. Wait for the round to start (QuickTest: about 5 s). The ability caption changes to `Q • READY`.
4. Press **Q**: the notice shows the ability name. The caption then reads `RECHARGING Ns` and counts down.
5. Press **Q** again while recharging: a `RECHARGING` notice, and no effect.
6. Switch characters during the recharge: the cooldown keeps counting.

Record which of these steps you can perform and what you observe. Do not mark a step as passed
unless you saw it in Play mode.

## 7. What to send back

- The Studio version (**Help → About**).
- Which file you opened (full path).
- Every red error and yellow warning from Output, verbatim.
- Whether the red "DID NOT START" panel appeared, and its full text.
- Screenshots of the screen during Play and of Explorer → PlayerGui.

## 8. What was changed for this check

- The server now publishes `BrainrotRemotes` before any world, art or persistence setup, so a later setup
  error can no longer stop the client from receiving state.
- The client waits for the remotes with a 15-second bound, and shows the red panel if they do not arrive.
- If the HUD fails to build, the client shows the red panel with the error text.
- `ScreenInsets` is set only if the Studio build supports it, so older builds still build the HUD.

These changes make failures visible and remove one structural ordering risk. **They do not prove the
cause of your session's failure.** That needs the Output from step 2 and the Studio check in section 5.
