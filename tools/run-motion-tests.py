"""Compile the production detector and run its actual Monkey C tests on FR255."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--sdk", type=Path, required=True)
parser.add_argument("--key", type=Path, required=True)
args = parser.parse_args()
project = args.project.resolve()
tests = project / "tests/ForgeMotionTests.mc.test"
expected = len(re.findall(r"\(:test\)", tests.read_text()))
if expected == 0:
    raise SystemExit("No motion tests found")

with tempfile.TemporaryDirectory(prefix="forge-motion-") as temp:
    root = Path(temp)
    for name in ("source", "resources"):
        shutil.copytree(project / name, root / name)
    shutil.copy2(project / "manifest.xml", root / "manifest.xml")
    (root / "monkey.jungle").write_text(
        "project.manifest = manifest.xml\nbase.sourcePath = source\nbase.resourcePath = resources\n"
    )
    shutil.copy2(tests, root / "source/ForgeMotionTests.mc")
    (root / "bin").mkdir()
    subprocess.run(
        [str(args.sdk / "bin/monkeyc"), "-f", "monkey.jungle", "-d", "fr255",
         "-o", "bin/tests.prg", "-y", str(args.key), "-t", "-w"],
        cwd=root, check=True,
    )
    result = subprocess.run(
        [str(args.sdk / "bin/monkeydo"), "bin/tests.prg", "fr255", "-t"],
        cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    print("Simulator command exit code:", result.returncode)
    # SDK 9.2 monkeydo exits 1 even for a completed passing Run No Evil run.
    # Missing verdict, skipped tests, failures, and runtime errors all fail here.
    verdict = rf"^PASSED \(passed={expected}, failed=0, errors=0\)$"
    if not re.search(verdict, result.stdout, re.MULTILINE):
        raise SystemExit(1)
