#!/usr/bin/env python3
"""Build, compile, analyze, execute tests, verify exports, and write an honest build report."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau-bin", type=Path, default=ROOT / ".tools/luau-0.744")
    parser.add_argument("--check-generated", action="store_true", help="Fail if committed/generated exports were stale before the build")
    args = parser.parse_args()
    binaries = {}
    for name in ("luau", "luau-compile", "luau-analyze"):
        candidate = args.luau_bin / name
        binaries[name] = str(candidate) if candidate.is_file() else shutil.which(name)
        if not binaries[name]:
            raise SystemExit("Luau tooling not found. Optional developer setup: python3 tools/bootstrap_luau.py. Studio users need only the .rbxlx file.")
    ARTIFACTS.mkdir(exist_ok=True)
    generated = [ROOT / "src/server/WorldData.luau", *sorted((ROOT / "places").glob("*.rbxlx"))]
    before = {str(p): digest(p) for p in generated if p.exists()}
    stages = []

    def run(key, title, command):
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (ARTIFACTS / f"check-{key}.log").write_text(result.stdout, encoding="utf-8")
        print(f"{'PASS' if result.returncode == 0 else 'FAIL'} {title}", flush=True)
        stages.append({"name": title, "passed": result.returncode == 0})
        if result.returncode:
            print(result.stdout)
            raise SystemExit(result.returncode)
        return result.stdout

    py = sys.executable
    run("build", "Studio place exports built", [py, "tools/build_place.py"])
    if args.check_generated:
        stale = [p for p, value in before.items() if digest(Path(p)) != value]
        if stale:
            raise SystemExit("Generated files were stale: " + ", ".join(stale))
    files = sorted([*ROOT.glob("src/**/*.luau"), *ROOT.glob("tests/**/*.luau")])
    run("compile", f"All {len(files)} Luau files compile", [binaries["luau-compile"], "--null", *map(str, files)])
    core = sorted(ROOT.glob("src/server/core/*.luau")) + [ROOT / "src/shared/Config.luau"]
    run("analyze", "Strict type analysis: authority modules + configuration", [binaries["luau-analyze"], *map(str, core)])
    core_output = run("core", "Core rules and 100 simulated 12-player rounds", [binaries["luau"], "tests/core.spec.luau"])
    adapter_output = run("adapters", "Production adapters against mocked Roblox services", [py, "tools/test_adapters.py", "--luau", binaries["luau"]])
    xml_output = run("place", "Place structure, loadable API properties and geometry", [py, "tools/verify_place.py"])
    hashes_before = {str(p): digest(p) for p in generated}
    run("deterministic", "Deterministic export rebuild", [py, "tools/build_place.py"])
    assert all(digest(Path(p)) == value for p, value in hashes_before.items()), "Non-deterministic generated output"
    run("whitespace", "Git diff whitespace check", ["git", "diff", "--check"])

    core_count = int(re.search(r"CORE RESULTS: (\d+) passed, 0 failed", core_output)[1])
    adapter_count = int(re.search(r"ADAPTER RESULTS: (\d+) passed, 0 failed", adapter_output)[1])
    place_count = int(re.search(r"Ran (\d+) tests", xml_output)[1])
    counts = {"core_luau": core_count, "mock_adapter_luau": adapter_count, "place_python": place_count}
    source_hash = hashlib.sha256()
    for path in sorted(ROOT.glob("src/**/*.luau")):
        source_hash.update(path.relative_to(ROOT).as_posix().encode())
        source_hash.update(path.read_bytes())
    places = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted((ROOT / "places").glob("*.rbxlx"))}
    verified_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    report = {
        "verified_at_utc": verified_at, "status": "automated_checks_passed_studio_unverified",
        "test_counts": counts, "total_passed": sum(counts.values()), "failed": 0,
        "luau_files_compiled": len(files), "source_sha256": source_hash.hexdigest(),
        "static_world_parts": 358, "pickup_slots": 48, "places": places, "stages": stages,
        "not_executed": ["Roblox Studio import", "Roblox client/server multiplayer simulation", "Engine physics and rendering", "Real touch-device input", "Bundled sound playback", "Published server test"],
    }
    (ARTIFACTS / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# BRAINROT ARENA — prototype build report", "", f"Verified: **{verified_at}**.", "",
        "**Automated checks passed. Roblox Studio / engine acceptance is still unverified.**",
        "This Linux workspace has no Roblox Studio installation or Roblox control connector.", "",
        "## Delivered", "",
        "- Two self-contained Studio-openable `.rbxlx` exports, plus editable Luau source and an optional Rojo project.",
        "- Original 358-part lobby/arena, four connected satellite platforms, and 48 collectible slots.",
        "- 12-second intermission → 180-second round → 9-second results; repeat automatically.",
        "- Atomic server pickups (+1/+5/+10), synchronized HUD/leaderboard, late joins, respawns and fall rescue.",
        "- Low gravity at 60 seconds for 25 seconds, then normal gravity; clean event/round resets.",
        "- Winner/tie/no-score announcements; session coins; one server-validated session cosmetic.",
        "- Responsive HUD with touch-control clearance, SFX toggle and reduced-motion setting.", "",
        "## Checks actually executed", "", "| Check | Result |", "|---|---:|",
        f"| Luau core tests (includes 100 × 12-player logical round simulations) | {core_count} passed |",
        f"| Real server/client scripts against mocked Roblox services | {adapter_count} passed |",
        f"| XML/API/geometry export tests | {place_count} passed |",
        f"| Official Luau compilation | {len(files)} files passed |",
        "| Strict analysis | 3 authority modules + Config passed |",
        "| Repeat build | Byte-for-byte deterministic |", "| Git whitespace check | Passed |", "",
        "The headless adapter tests validate code contracts, not Roblox physics, actual networking, UI rendering, or audio.", "",
        "## Remaining acceptance work", "",
        "Open `places/BrainrotArena-QuickTest.rbxlx` in Roblox Studio and use its Test tab to start **2 clients**.",
        "Confirm collecting, jumping during low gravity, the winner card, and the next round on both clients.",
        "Use Device Emulator to verify touch controls/text and check Output for errors. See [TESTING.md](TESTING.md).",
        "No code pasting, plugin installation, API keys, asset uploads, or monetization setup is required.", "",
        "## Deliberate limits", "",
        "- Coins/halo are session-only, not saved between server visits.",
        "- One map and one event; no pets, additional maps, monetization, or persistent economy.",
        "- Movement checks are a basic sanity layer, not a complete exploit-prevention system.",
        "- Bundled pickup tone availability and exact visual polish still need the Studio/device pass.", "",
        "## Export integrity", "", f"Source SHA-256: `{source_hash.hexdigest()}`", "",
    ]
    for name, info in places.items():
        lines += [f"- `{name}` — {info['bytes']:,} bytes; SHA-256 `{info['sha256']}`"]
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs/BUILD_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\n{sum(counts.values())} tests passed; 0 failed. Studio engine not available, not claimed tested.")
    print("Report: docs/BUILD_REPORT.md | Machine-readable: artifacts/verification.json")


if __name__ == "__main__":
    main()
