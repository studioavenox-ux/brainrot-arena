# Required asset inventory

The project uses **procedural Roblox primitives and script-built UI**, not a separate imported art pack.

## Included assets and their definitions

- **Editable lobby/arena:** baked into both `places/*.rbxlx` files; editable source specification in `tools/world.py`; generated runtime equivalent in `src/server/WorldData.luau`; loader/builder in `src/server/WorldService.luau`.
- **Brain Cells and pickup effects:** server roots in `src/server/Main.server.luau`; client lobes, animation and sparks in `src/client/Effects.luau`; rarity/color constants in `src/shared/Config.luau`.
- **Pulse Halo:** procedural geometry in `src/server/Main.server.luau`, with price/ownership rules in `Config.luau` and `core/RoundMachine.luau`.
- **HUD, wordmark, panels and UI brain icon:** created from Roblox UI primitives in `src/client/Hud.luau`. No image decal, uploaded logo or font file is required.
- **Lighting and signs:** included in the place, builder and world data.

No custom `.rbxm`, `.fbx`, `.obj`, mesh, decal/image, sound file or externally hosted game asset is required or missing. All production source files are also embedded in the place files.

## Roblox-provided resources — external platform dependencies

The existing implementation references one short tone and six sky textures using local `rbxasset://` URLs. Their exact paths are recorded in `asset-manifest.json`. These resources belong to the Roblox installation; this ZIP does **not** redistribute Roblox engine/bundled files.

Standard Roblox fonts, avatars, controls and camera behavior also depend on the installed platform. Their rendering/playback, including the tone and sky texture availability, has **not** been checked inside Windows Studio here. See `docs/DEPENDENCIES.md` and the Windows test steps in the root README.

The source/place implementation and its existing asset references are preserved, not replaced with invented asset IDs or placeholder downloads.
