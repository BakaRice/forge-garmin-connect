from pathlib import Path
import argparse, re, shutil, subprocess, tempfile
parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--sdk", type=Path, required=True)
parser.add_argument("--key", type=Path, required=True)
args = parser.parse_args()
project = args.project.resolve()
# Compile the real ForgeApp method with only its time source replaced.
# Expose the hidden method in this temporary build, without adding a test API
# to the production app or duplicating the debounce calculation.
with tempfile.TemporaryDirectory(prefix="forge-debounce-") as temp:
    root = Path(temp)
    for name in ("source", "resources"):
        shutil.copytree(project / name, root / name)
    shutil.copy2(project / "manifest.xml", root / "manifest.xml")
    (root / "monkey.jungle").write_text("project.manifest = manifest.xml\nbase.sourcePath = source\nbase.resourcePath = resources\n")
    app = root / "source/ForgeApp.mc"
    text = app.read_text()
    assert text.count("System.getTimer()") == 1
    assert text.count("hidden function debounced()") == 1
    text = text.replace("System.getTimer()", "ForgeTestClock.getTimer()")
    text = text.replace("hidden function debounced()", "function debounced()")
    app.write_text(text)
    shutil.copy2(project / "tests/ForgeDebounceTests.mc.test", root / "source/ForgeDebounceTests.mc")
    (root / "bin").mkdir()
    subprocess.run([str(args.sdk / "bin/monkeyc"), "-f", "monkey.jungle", "-d", "fr255", "-o", "bin/tests.prg", "-y", str(args.key), "-t", "-w"], cwd=root, check=True)
    result = subprocess.run([str(args.sdk / "bin/monkeydo"), "bin/tests.prg", "fr255", "-t"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    print("Simulator command exit code:", result.returncode)
    # This SDK command exits 1 even when Run No Evil reports all tests passed.
    # Require its explicit completed six-test verdict and print the process exit.
    passed = re.search(r"^PASSED \(passed=6, failed=0, errors=0\)$", result.stdout, re.MULTILINE)
    if not passed:
        raise SystemExit(1)
