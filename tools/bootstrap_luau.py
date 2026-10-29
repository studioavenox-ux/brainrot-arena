#!/usr/bin/env python3
"""Optional developer tooling. Opening either .rbxlx in Studio needs NONE of this."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.744"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if not shutil.which("make") or not shutil.which("g++"):
        raise SystemExit("Developer tests require make + g++, or Luau CLI tools on PATH. Studio users: open places/BrainrotArena.rbxlx instead.")
    tools = ROOT / ".tools"
    tools.mkdir(exist_ok=True)
    source = tools / f"luau-{VERSION}"
    if not source.exists():
        archive = tools / f"luau-{VERSION}.tar.gz"
        urllib.request.urlretrieve(f"https://codeload.github.com/luau-lang/luau/tar.gz/refs/tags/{VERSION}", archive)
        with tarfile.open(archive) as tar:
            # Refuse path traversal even though this archive comes from the official repository.
            for member in tar.getmembers():
                destination = (tools / member.name).resolve()
                if not destination.is_relative_to(tools.resolve()) or member.issym() or member.islnk():
                    raise SystemExit("Unexpected archive member")
            tar.extractall(tools)
    subprocess.run(["make", "config=release", f"-j{max(1,args.jobs)}", "luau", "luau-compile", "luau-analyze"], cwd=source, check=True)
    print(f"Developer tooling ready in {source.relative_to(ROOT)}. Run: python3 tools/check.py")


if __name__ == "__main__":
    main()
