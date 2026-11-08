# Package completeness and dependencies

This is the complete **current prototype**, not a claim that deferred features have been implemented. Packaging preserves the shipped gameplay scripts and both place files byte-for-byte.

**This delivery adds a visual redesign** (see [VISUAL_CHANGES.md](VISUAL_CHANGES.md)): new environment art, materials, lighting, signage, entrance portal and rarity silhouettes. Gameplay rules — rounds, scoring, collectibles, coins, cosmetics and networking — are unchanged, and the walkable geometry is byte-identical to the pre-redesign build (frozen in `tests/fixtures/world-baseline.json` and asserted by `tools/artcheck.py`).

## Included project files

| Item | Included location | Status |
|---|---|---|
| Standard Roblox place, with editable baked map and embedded scripts | `places/BrainrotArena.rbxlx` | Included |
| Short-cycle Studio test place, with the same embedded implementation | `places/BrainrotArena-QuickTest.rbxlx` | Included |
| Client entry point, HUD, rarity silhouettes and effects | `src/client/` — 4 Luau files | Included |
| Server entry point, world builder, art service and generated world data | `src/server/` — 4 Luau files | Included |
| Authoritative round, collectible and movement modules | `src/server/core/` — 3 Luau files | Included |
| Shared configuration and generated art-direction mirror | `src/shared/Config.luau`, `src/shared/ArtDirection.luau` — 2 Luau files | Included |
| Original map, brain/halo geometry, UI and pickup effects | Baked into the place and/or generated from the included source | Included; no separate binary model/mesh files are required |
| Visual art direction source (palette, materials, lighting, hierarchy) | `tools/theme.py` | Included |
| Art-direction verification and review renders | `tools/artcheck.py`, `tools/preview.py`, `docs/previews/` | Included |
| Frozen pre-redesign collidable geometry | `tests/fixtures/world-baseline.json` | Included |
| Asset inventory | `assets/README.md`, `assets/asset-manifest.json` | Included |
| Windows opening and testing instructions | Root `README.md` | Included |
| Acceptance checklist, architecture and original build report | `docs/` | Included |
| Automated tests and pinned API fixture | `tests/` | Included |
| Deterministic build, verification and packaging scripts | `tools/` | Included |
| Optional Rojo project and GitHub verification workflow | `default.project.json`, `.github/workflows/check.yml` | Included |
| Original automated results | `artifacts/verification.json` | Included unchanged |
| File inventory with per-file SHA-256 checksums | `MANIFEST.json` at the ZIP's project root | Generated and included; it excludes its own checksum |

**Missing required project files/custom game assets: none found in the package audit.** The ZIP contains both places and all 10 production Luau files. Source and places are checked against the preserved implementation's verification hashes. The ZIP's CRC and per-file checksums are validated after creation.

## Required installed platform — not included in the ZIP

- A supported Windows PC with the current **Roblox Studio for Windows** installed.
- A Roblox account, sign-in and an internet connection for Studio/platform setup and normal Roblox resources.
- Roblox's standard engine, fonts, character/controller/camera scripts and platform-provided avatars. These come from Roblox, not from this project.
- The bundled pickup tone `rbxasset://sounds/electronicpingshort.wav` and six `rbxasset://textures/sky/sky512_*.tex` resources referenced by the current implementation. The exact seven URLs are in the asset manifest.

Roblox Studio, its engine/bundled files, account credentials and installers are **not** redistributable project assets and are not included. Availability of the specified sound/sky files in an actual Windows Studio installation is **unverified**; this is an outstanding engine check, not a missing custom project file. No game logic or asset reference was changed to hide that limitation.

## Not required for opening or testing in Studio

You do **not** need Python, the Luau CLI, Rojo, Node.js/npm, Git, a Roblox plugin, API keys, Studio API-service access, Toolbox downloads, custom asset uploads, a web server, paid assets or publishing.

For optional filesystem-based rebuilding/testing only:

- **Python 3.10+** is required by the included build/export verification scripts. They use the Python standard library; no pip packages are needed. The optional `tools/preview.py` review renderer additionally needs `numpy` and `Pillow`, and is **never** part of the game or required to open either place.
- Official **Luau 0.744** CLI tools are required to repeat compilation, strict analysis and headless Luau tests. Compiled development tools are not bundled. The included bootstrap script targets systems with `make` and `g++`; it is not a Windows Studio setup step.
- **Git** is used by the optional all-checks tool's whitespace check. A ZIP extraction is not a Git checkout. The export verifier can run independently with Python, while the Git-dependent check should run from the repository.
- **Rojo** is optional for a source-sync workflow; neither its CLI nor Studio plugin is bundled or required by the ready-to-open places.

The development cache, prior temporary logs, compiled Luau binaries and `.git` history/credentials are intentionally excluded, not missing game dependencies. The concept board is reference material, not a runtime asset dependency.

## Verification boundaries

The report records **72 core Luau tests + 32 mocked production-adapter tests + 30 export tests + 24 art-direction tests = 158 passing tests**. It is included with its original verification timestamp; those results are not relabeled as a new Windows playtest.

For this packaging delivery, the XML/source/geometry export checks and archive integrity checks are run again, including a check from a clean ZIP extraction. The packaged production source and both places are identical to the verification hashes recorded in `artifacts/verification.json`.

Roblox Studio import, Windows execution, actual client/server networking, engine physics, rendered UI, real touch input and bundled audio playback still require the included Studio acceptance checklist. No Roblox place was published from this environment.

Persistent coins/cosmetics, extra maps/events, pets and monetization remain deliberately deferred features, not files accidentally left out of the ZIP.
