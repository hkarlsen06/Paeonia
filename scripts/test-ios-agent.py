#!/usr/bin/python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


SOURCE = Path(__file__).with_name("ios-agent")
loader = importlib.machinery.SourceFileLoader("ios_agent", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
agent = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = agent
loader.exec_module(agent)


def device(udid="00008150-000230D82E40401C", **overrides):
    properties = {
        "hardware": {"udid": udid, "fidelity": "physical", "productFamily": "iPhone"},
        "connection": {"state": "connected", "pairingState": "paired"},
        "state": {"name": "spare", "developerModeStatus": {"enabled": {}}, "areDeveloperDiskImageServicesAvailable": True},
    }
    for section, values in overrides.items():
        properties[section].update(values)
    return {"properties": properties, "capabilities": [
        {"featureIdentifier": "com.apple.coredevice.feature." + name}
        for name in ("installapp", "launchapplication", "processcontrol")
    ]}


class PolicyTests(unittest.TestCase):
    def test_caps_workers_and_testing(self):
        args = agent.build_arguments(["test", "-jobs", "16", "-jobs=8", "-parallel-testing-enabled", "YES"])
        self.assertEqual(args.count("-jobs"), 1)
        self.assertEqual(args[args.index("-jobs") + 1], "2")
        self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")

    def test_extra_simulators_require_opt_in(self):
        with mock.patch.dict(os.environ, {"IOS_AGENT_SIMULATORS": "1"}):
            with self.assertRaises(ValueError):
                agent.build_arguments(["test", "-destination", "platform=iOS Simulator,name=Shared iPhone 2"])
            for destination in ("id=" + agent.SIMULATORS[1][1], "name=Shared iPhone 2"):
                for argument in (["-destination", destination], ["-destination=" + destination]):
                    with self.assertRaises(ValueError):
                        agent.build_arguments(["test"] + argument)
            agent.check_simulator("Shared iPhone")
        with mock.patch.dict(os.environ, {"IOS_AGENT_SIMULATORS": "2"}):
            agent.check_simulator(agent.SIMULATORS[1][1])

    def test_xcrun_sdk_prefix_still_uses_host_queue(self):
        with mock.patch.object(agent, "xcodebuild", return_value=0) as build:
            agent.xcrun(["--sdk", "iphoneos", "xcodebuild", "build"])
            build.assert_called_once_with(["build"], ["/usr/bin/xcrun", "--sdk", "iphoneos", "xcodebuild"])

    def test_user_worker_override(self):
        with mock.patch.dict(os.environ, {"XCODE_AGENT_JOBS": "1"}):
            args = agent.build_arguments(["build", "-jobs", "18"])
            self.assertEqual(args[args.index("-jobs") + 1], "1")
        with mock.patch.dict(os.environ, {"XCODE_AGENT_JOBS": "0"}):
            with self.assertRaises(ValueError):
                agent.build_arguments(["build"])

    def test_xcrun_passthrough_replaces_supervisor(self):
        class Replaced(Exception):
            pass
        with mock.patch.object(agent.os, "execv", side_effect=Replaced) as execute:
            with self.assertRaises(Replaced):
                agent.xcrun(["simctl", "io", "Shared iPhone", "recordVideo", "capture.mp4"])
            execute.assert_called_once_with("/usr/bin/xcrun", ["/usr/bin/xcrun", "simctl", "io", "Shared iPhone", "recordVideo", "capture.mp4"])

    def test_only_approved_ready_unlocked_physical_phone_is_selected(self):
        inputs = [device(), device("primary"), device(connection={"state": "unavailable"}),
                  device(hardware={"fidelity": "simulated"}), device(state={"developerModeStatus": {}})]
        result = agent.physical_devices({"devices": inputs}, lambda udid: {"passcodeRequired": False, "unlockedSinceBoot": True})
        self.assertEqual([item.eligible for item in result], [True, False, False, False])

    def test_locked_or_unprepared_phone_is_ineligible(self):
        result = agent.physical_devices({"devices": [device()]}, lambda udid: {"passcodeRequired": True, "unlockedSinceBoot": True})
        self.assertFalse(result[0].eligible)
        unprepared = device()
        unprepared["capabilities"] = []
        result = agent.physical_devices({"devices": [unprepared]}, lambda udid: self.fail("must not inspect unprepared phone"))
        self.assertFalse(result[0].eligible)

    def test_discovery_failure_falls_back(self):
        with mock.patch.object(agent, "discover", side_effect=subprocess.TimeoutExpired("devicectl", 8)), mock.patch("builtins.print") as output:
            self.assertEqual(agent.main(["destination"]), 0)
            output.assert_any_call("platform=iOS Simulator,name=Shared iPhone")


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.events = self.root / "events"
        self.fake = self.root / "fake-build"
        self.fake.write_text(f'''#!{sys.executable}
import os, time
from pathlib import Path
p = Path({str(self.events)!r})
with p.open("a") as f: f.write(f"start {{os.getpid()}} {{time.monotonic()}}\\n")
time.sleep(0.4)
with p.open("a") as f: f.write(f"end {{os.getpid()}} {{time.monotonic()}}\\n")
''')
        self.fake.chmod(0o755)
        self.runner = self.root / "run.py"
        self.runner.write_text(f'''import runpy
from pathlib import Path
m = runpy.run_path({str(SOURCE)!r}, run_name="ios_agent_test")
raise SystemExit(m["xcodebuild"](["build"], {str(self.fake)!r}, Path({str(self.root / "queue")!r})))
''')

    def start(self):
        child = subprocess.Popen([sys.executable, str(self.runner)], stdout=subprocess.DEVNULL)
        def stop():
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        self.addCleanup(stop)
        return child

    def wait_started(self):
        deadline = time.monotonic() + 20
        while (not self.events.exists() or not self.events.read_text().strip()) and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(self.events.exists())

    def test_concurrent_builds_never_overlap(self):
        children = [self.start() for unused in range(3)]
        for child in children:
            self.assertEqual(child.wait(timeout=30), 0)
        self.assertEqual([line.split()[0] for line in self.events.read_text().splitlines()], ["start", "end"] * 3)
        self.assertFalse((self.root / "queue").exists())

    def test_legacy_ancestor_lock_is_borrowed_without_deadlock(self):
        directory = self.root / "queue"
        directory.mkdir()
        (directory / "owner").write_text(f"{os.getpid()} legacy-wrapper\n")
        self.assertEqual(self.start().wait(timeout=5), 0)
        self.assertTrue(directory.exists())

    def test_dead_owner_is_reaped(self):
        directory = self.root / "queue"
        directory.mkdir()
        (directory / "owner").write_text("2147483647 gone\n")
        self.assertEqual(self.start().wait(timeout=5), 0)
        self.assertFalse(directory.exists())

    def test_killed_supervisor_does_not_allow_overlapping_build(self):
        first = self.start()
        self.wait_started()
        first.kill()
        first.wait(timeout=5)
        second = self.start()
        self.assertEqual(second.wait(timeout=10), 0)
        self.assertEqual([line.split()[0] for line in self.events.read_text().splitlines()], ["start", "end"] * 2)

    def test_cancellation_stops_build_before_releasing_queue(self):
        child = self.start()
        self.wait_started()
        build_pid = int(self.events.read_text().split()[1])
        child.send_signal(signal.SIGTERM)
        self.assertEqual(child.wait(timeout=5), 143)
        self.assertFalse(agent.process_alive(build_pid))
        self.assertFalse((self.root / "queue").exists())


class SimulatorLeaseTests(unittest.TestCase):
    def test_only_current_live_explicit_reservations_keep_extras_booted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            owners = root / "locks"
            lease_root = root / "leases"
            owner = owners / "simulator-2/owner"
            owner.parent.mkdir(parents=True)
            owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
            with mock.patch.dict(os.environ, {"IOS_AGENT_SIMULATORS": "2"}):
                agent.grant_simulator("Shared iPhone 2", lease_root, owners)
            self.assertTrue(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            owner.write_text(f"checkout||{int(time.time())}")
            self.assertTrue(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            owner.write_text(f"checkout||{int(time.time()) - 601}")
            self.assertFalse(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            with mock.patch.dict(os.environ, {"IOS_AGENT_SIMULATORS": "2"}):
                agent.grant_simulator("Shared iPhone 2", lease_root, owners, ttl_seconds=1800)
                agent.grant_simulator("Shared iPhone 2", lease_root, owners)
            self.assertTrue(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            owner.write_text(f"checkout||{int(time.time()) - 1801}")
            self.assertFalse(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            owner.write_text(f"other-checkout|{os.getpid()}|{int(time.time())}")
            self.assertFalse(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))
            devices = {"devices": {"runtime": [
                {"name": name, "udid": udid, "state": "Booted"}
                for name, udid in agent.SIMULATORS
            ]}}
            with mock.patch.object(agent.subprocess, "run", return_value=mock.Mock(stdout=json.dumps(devices))) as run:
                agent.enforce_simulators(lease_root)
                shutdowns = [call.args[0][-1] for call in run.call_args_list if "shutdown" in call.args[0]]
                self.assertEqual(shutdowns, [agent.SIMULATORS[1][1], agent.SIMULATORS[2][1]])
            owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
            with mock.patch.object(agent.subprocess, "run", return_value=mock.Mock(stdout=json.dumps(devices))) as run:
                agent.enforce_simulators(lease_root)
                shutdowns = [call.args[0][-1] for call in run.call_args_list if "shutdown" in call.args[0]]
                self.assertEqual(shutdowns, [agent.SIMULATORS[2][1]])
            owner.parent.rename(owners / "released")
            owner.parent.mkdir()
            owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
            self.assertFalse(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))


if __name__ == "__main__":
    unittest.main()
