"""Build real motion/session sources with only Garmin OS boundaries replaced."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--sdk", type=Path, required=True)
parser.add_argument("--key", type=Path, required=True)
parser.add_argument("--build-dir", type=Path, required=True)
parser.add_argument("--prepare-only", action="store_true")
parser.add_argument("--red-ui-stub", action="store_true")
parser.add_argument("--red-stub", action="store_true", help="Demonstrate assertion failures against unimplemented interfaces")
args = parser.parse_args()
project = args.project.resolve()
root = args.build_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
(root / "source").mkdir(exist_ok=True)
shutil.copytree(project / "resources", root / "resources", dirs_exist_ok=True)
shutil.copy2(project / "manifest.xml", root / "manifest.xml")
test_text = (project / "tests/ForgeMotionIntegrationTests.mc.test").read_text()
expected = len(re.findall(r"\(:test\)", test_text))
(root / "source/IntegrationTests.mc").write_text(test_text)
for name in ("ForgeMotionDetector.mc", "ForgeMotion.mc", "ForgeMotionFit.mc", "ForgeSession.mc", "ForgeState.mc", "ForgeApp.mc", "ForgeDelegate.mc"):
    path = project / "source" / name
    if not path.exists():
        continue
    source = path.read_text()
    for module, facade in (("Sensor", "IntegrationSensor"), ("ActivityRecording", "IntegrationRecording"), ("Activity", "IntegrationActivity")):
        source = source.replace("using Toybox." + module + ";", "")
        source = source.replace(module + ".", facade + ".")
    source = source.replace("as IntegrationSensor.SensorData", "as IntegrationData")
    source = source.replace("Application.getApp()", "IntegrationApplication.getApp()")
    source = source.replace("System.getTimer()", "IntegrationClock.now()")
    source = source.replace("System.getDeviceSettings()", "IntegrationClock.getDeviceSettings()")
    source = source.replace("System.exit()", "IntegrationUi.exit()")
    source = source.replace("WatchUi.requestUpdate()", "IntegrationUi.requestUpdate()")
    source = source.replace("new Timer.Timer()", "new IntegrationTimer.Timer()")
    (root / "source" / name).write_text(source)
if args.red_ui_stub:
    app_path = root / "source/ForgeApp.mc"
    app = app_path.read_text().replace("_metricsPage = 1 - _metricsPage;", "_metricsPage = 0;")
    app = app.replace("if (_session != null) { _session.stopMotion(); }", "")
    app_path.write_text(app)
if args.red_stub:
    (root / "source/ForgeMotion.mc").write_text("""class ForgeMotion {
    function initialize() {} function start(callback) {} function stop() {} function reset() {}
    function getCount() { return null; } function getCadence() { return null; }
    function getPhase() { return 0; } function getStatus() { return "idle"; }
}""")
(root / "monkey.jungle").write_text("project.manifest = manifest.xml\nbase.sourcePath = source\nbase.resourcePath = resources\n")
(root / "bin").mkdir(exist_ok=True)
subprocess.run([str(args.sdk / "bin/monkeyc"), "-f", "monkey.jungle", "-d", "fr255", "-o", "bin/tests.prg", "-y", str(args.key), "-t", "-w"], cwd=root, check=True)
print("Expected integration tests:", expected)
if args.prepare_only:
    raise SystemExit(0)
result = subprocess.run([str(args.sdk / "bin/monkeydo"), "bin/tests.prg", "fr255", "-t"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(result.stdout, end="")
print("Simulator command exit code:", result.returncode)
verdict = rf"^PASSED \(passed={expected}, failed=0, errors=0\)$"
if not re.search(verdict, result.stdout, re.MULTILINE):
    raise SystemExit(1)
