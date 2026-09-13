#!/usr/bin/env python3
"""Build the checked-out Debug app; retain logs locally without launching it."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--package-cache", type=Path)
parser.add_argument("--derived-data", type=Path)
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]
output = source / ".build-local"
output.mkdir(exist_ok=True)
command = ["xcodebuild", "-project", str(source / "Mythic.xcodeproj"),
           "-scheme", "Mythic", "-configuration", "Debug",
           "-destination", "platform=macOS,arch=arm64",
           "-derivedDataPath", str(args.derived_data or output / "DerivedData"),
           "-disableAutomaticPackageResolution", "-skipPackageUpdates",
           "CODE_SIGNING_ALLOWED=NO", "build"]
if args.package_cache:
    command[1:1] = ["-clonedSourcePackagesDirPath", str(args.package_cache)]
environment = dict(os.environ)
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
log = output / "debug-build.log"
print(f"Build log: {log}", flush=True)
with log.open("w") as stream:
    try:
        result = subprocess.run(command, cwd=source, env=environment,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=900)
    except subprocess.TimeoutExpired:
        raise SystemExit("Build timed out after 15 minutes; inspect the build log.")
print("BUILD PASSED" if result.returncode == 0 else f"BUILD FAILED ({result.returncode})")
raise SystemExit(result.returncode)
