#!/usr/bin/env python3
"""Bundle the unchanged prototype, assets/inventory, Windows README and integrity manifest."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/BrainrotArena-Project.zip"
SOURCE_FILES = (
    "src/client/Effects.luau", "src/client/Hud.luau", "src/client/Main.client.luau",
    "src/server/Main.server.luau", "src/server/WorldData.luau", "src/server/WorldService.luau",
    "src/server/core/MovementGuard.luau", "src/server/core/PickupLedger.luau",
    "src/server/core/RoundMachine.luau", "src/shared/Config.luau",
)
PLACE_FILES = ("places/BrainrotArena.rbxlx", "places/BrainrotArena-QuickTest.rbxlx")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def runtime_resource_urls(paths):
    resources = set()
    for path in paths:
        resources.update(re.findall(r'''rbxasset://[^\s"'<>]+''', path.read_text(encoding="utf-8")))
    return sorted(resources)


def main():
    required = [
        *SOURCE_FILES, *PLACE_FILES, "README.md", "default.project.json", ".gitignore",
        "docs/BUILD_REPORT.md", "docs/TESTING.md", "docs/ARCHITECTURE.md", "docs/DEPENDENCIES.md",
        "assets/README.md", "assets/asset-manifest.json", "artifacts/verification.json",
        "tools/build_place.py", "tools/world.py", "tools/verify_place.py", "tests/fixtures/roblox-api.json",
    ]
    missing = [name for name in required if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit("Missing required project files:\n" + "\n".join(missing))

    # Do not rebuild or silently change the game to package it. Verify the preserved build instead.
    verification = json.loads((ROOT / "artifacts/verification.json").read_text(encoding="utf-8"))
    source_hash = hashlib.sha256()
    sources = sorted((ROOT / "src").rglob("*.luau"))
    assert {p.relative_to(ROOT).as_posix() for p in sources} == set(SOURCE_FILES), "Unexpected/missing production scripts"
    for path in sources:
        source_hash.update(path.relative_to(ROOT).as_posix().encode())
        source_hash.update(path.read_bytes())
    assert source_hash.hexdigest() == verification["source_sha256"], "Production source differs from the recorded verified implementation"
    for place in PLACE_FILES:
        path = ROOT / place
        assert sha256(path.read_bytes()) == verification["places"][path.name]["sha256"], f"Changed place: {place}"

    assets = json.loads((ROOT / "assets/asset-manifest.json").read_text(encoding="utf-8"))
    actual_resources = runtime_resource_urls([*sources, *(ROOT / name for name in PLACE_FILES)])
    assert actual_resources == sorted(assets["roblox_bundled_resource_urls"]), "Asset resource inventory is stale"
    for asset in assets["included_procedural_asset_sources"]:
        assert (ROOT / asset).is_file(), f"Missing procedural asset source: {asset}"
    for path in sources:
        assert not re.search(r"rbxassetid://|require\s*\(\s*\d", path.read_text(encoding="utf-8")), f"Undeclared external game asset: {path}"

    files = [ROOT / "README.md", ROOT / "default.project.json", ROOT / ".gitignore", ROOT / "artifacts/verification.json"]
    for directory in ("places", "src", "assets", "tests", "tools", "docs", ".github"):
        files.extend(p for p in (ROOT / directory).rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
    files = sorted(set(files))
    entries = [
        {"path": p.relative_to(ROOT).as_posix(), "bytes": p.stat().st_size, "sha256": sha256(p.read_bytes())}
        for p in files
    ]
    manifest = {
        "format_version": 1,
        "project": "BRAINROT ARENA",
        "scope": "Complete current prototype; production scripts and places preserved byte-for-byte",
        "files": entries,
        "file_count_excluding_manifest": len(entries),
        "production_script_count": len(sources),
        "place_count": len(PLACE_FILES),
        "source_sha256": source_hash.hexdigest(),
        "prior_verification_timestamp_utc": verification["verified_at_utc"],
        "prior_automated_tests_passed": verification["total_passed"],
        "studio_engine_playtest_performed": False,
        "missing_required_project_files": [],
        "missing_required_custom_assets": [],
        "required_installed_platform": "Roblox Studio for Windows, Roblox account and normal platform resources",
        "roblox_bundled_resource_urls": actual_resources,
        "bundled_resource_availability_verified_in_studio": False,
        "documentation": {"windows_instructions": "README.md", "dependencies": "docs/DEPENDENCIES.md", "assets": "assets/asset-manifest.json"},
        "manifest_note": "Per-file hashes cover all payload files; MANIFEST.json cannot include its own hash.",
    }
    manifest_bytes = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    OUTPUT.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        def add(name, payload):
            info = zipfile.ZipInfo("BrainrotArena/" + name, date_time=(2026, 1, 1, 0, 0, 0))
            archive.writestr(info, payload, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        for path in files:
            add(path.relative_to(ROOT).as_posix(), path.read_bytes())
        add("MANIFEST.json", manifest_bytes)

    with zipfile.ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None, "Archive CRC failure"
        assert len(archive.namelist()) == len(entries) + 1
        expected = {"BrainrotArena/" + entry["path"] for entry in entries} | {"BrainrotArena/MANIFEST.json"}
        assert set(archive.namelist()) == expected, "Unexpected or omitted archive members"
        for entry in entries:
            assert sha256(archive.read("BrainrotArena/" + entry["path"])) == entry["sha256"], f"Hash failure: {entry['path']}"
        for name in archive.namelist():
            path = PurePosixPath(name)
            assert not path.is_absolute() and ".." not in path.parts
            assert ".git" not in path.parts and ".tools" not in path.parts and "__pycache__" not in path.parts

    (ROOT / "artifacts/package-manifest.json").write_bytes(manifest_bytes)
    checksum = sha256(OUTPUT.read_bytes())
    OUTPUT.with_suffix(".zip.sha256").write_text(f"{checksum}  {OUTPUT.name}\n", encoding="ascii")
    print(f"Packaged {len(entries) + 1} files -> {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size:,} bytes)")
    print(f"Preserved: {len(PLACE_FILES)} places + {len(sources)} production Luau files; no required project/custom-asset files missing")
    print(f"Audited {len(actual_resources)} external Roblox-bundled resource URLs (Studio availability still unverified)")
    print(f"Archive CRC and all {len(entries)} payload SHA-256 checks passed")
    print(f"ZIP SHA-256: {checksum}")


if __name__ == "__main__":
    main()
