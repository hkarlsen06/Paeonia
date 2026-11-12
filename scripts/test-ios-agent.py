#!/usr/bin/python3
import fcntl
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
        self.assertEqual(args[args.index("-jobs") + 1], "6")
        self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")

    def test_pool_is_three_simulators_unless_made_smaller(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("IOS_AGENT_SIMULATORS", None)
            agent.build_arguments(["test", "-destination", "platform=iOS Simulator,name=Shared iPhone 3"])
            with self.assertRaises(ValueError):
                agent.build_arguments(["test", "-destination", "platform=iOS Simulator,name=iPhone 17 Pro"])
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

    def test_each_invocation_queues_for_what_it_uses(self):
        simulator = ["-destination", "platform=iOS Simulator,name=Shared iPhone"]
        phone = ["-destination", "platform=iOS,id=00008150-000230D82E40401C"]
        for arguments, expected in (
            (["build"], ["build"]),
            ([], ["build"]),
            (["build-for-testing"] + phone, ["build"]),
            (["test"] + simulator, ["build"]),
            (["test"] + phone, ["device-00008150-000230D82E40401C", "build"]),
            (["test"] + phone + phone, ["device-00008150-000230D82E40401C", "build"]),
            (["test-without-building", "-derivedDataPath", "build"] + simulator, []),
            (["test-without-building"] + simulator, []),
            (["test-without-building"] + phone, ["device-00008150-000230D82E40401C"]),
            (["build", "test-without-building"] + simulator, ["build"]),
            (["test", "-destination", "platform=macOS,name=My Mac"], ["build"]),
        ):
            self.assertEqual(agent.resources(arguments), expected, arguments)
        with self.assertRaises(ValueError):
            agent.resources(["test-without-building", "-destination", "platform=iOS,name=Spare"])

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


PHONE = "platform=iOS,id=00008150-000230D82E40401C"


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.events = self.root / "events"
        self.events.write_text("")
        self.queues = self.root / "queues"
        self.runner = self.root / "run.py"
        self.fake = self.root / "fake-build"
        self.fake.write_text(f"""#!{sys.executable}
import os, subprocess, sys, time
def note(kind):
    with open({str(self.events)!r}, "a") as events:
        events.write(kind + " " + os.environ.get("FAKE_TAG", "-") + " " + str(os.getpid()) + "\\n")
note("start")
if os.environ.get("FAKE_NESTED"):
    environment = dict(os.environ, FAKE_TAG="inner")
    del environment["FAKE_NESTED"]
    subprocess.run([sys.executable, {str(self.runner)!r}], env=environment, check=True)
time.sleep(float(os.environ.get("FAKE_SLEEP", "0.4")))
note("end")
""")
        self.fake.chmod(0o755)
        self.runner.write_text(f"""import os, runpy, sys
from pathlib import Path
m = runpy.run_path({str(SOURCE)!r}, run_name="ios_agent_test")
controller = m["xcodebuild"].__globals__
if "TEST_STALE" in os.environ:
    controller["STALE"] = float(os.environ["TEST_STALE"])
if "TEST_LABEL" in os.environ:
    controller["requester"] = lambda: os.environ["TEST_LABEL"]
raise SystemExit(m["xcodebuild"](sys.argv[1:] or ["build"], {str(self.fake)!r}, Path({str(self.queues)!r})))
""")

    def start(self, *arguments, tag="-", **environment):
        child = subprocess.Popen([sys.executable, str(self.runner), *arguments], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, env=dict(os.environ, FAKE_TAG=tag, **environment))
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

    def wait_for(self, condition, message):
        deadline = time.monotonic() + 20
        while not condition():
            self.assertLess(time.monotonic(), deadline, message)
            time.sleep(0.02)

    def log(self):
        return [line.split()[:2] for line in self.events.read_text().splitlines()]

    def tickets(self, resource="build"):
        return sorted(path for path in (self.queues / resource).glob("[0-9]*") if not path.suffix)

    def starts(self):
        return [tag for kind, tag in self.log() if kind == "start"]

    def hold(self, *arguments, tag="holder", **environment):
        child = self.start(*arguments, tag=tag, **dict({"FAKE_SLEEP": "1.5"}, **environment))
        self.wait_for(lambda: ["start", tag] in self.log(), f"{tag} never started")
        return child

    def enqueue(self, *arguments, **options):
        waiting = len(self.tickets())
        child = self.start(*arguments, **options)
        self.wait_for(lambda: len(self.tickets()) > waiting, "the run never joined the queue")
        return child

    def test_concurrent_builds_never_overlap(self):
        children = [self.start() for unused in range(3)]
        for child in children:
            self.assertEqual(child.wait(timeout=30), 0)
        self.assertEqual([kind for kind, unused in self.log()], ["start", "end"] * 3)
        self.assertEqual(self.tickets(), [])

    def test_builds_start_in_arrival_order(self):
        holder = self.hold()
        waiters = [self.enqueue(tag=tag, FAKE_SLEEP="0.05") for tag in ("first", "second", "third")]
        for child in [holder] + waiters:
            self.assertEqual(child.wait(timeout=30), 0)
        self.assertEqual(self.starts(), ["holder", "first", "second", "third"])

    def test_killed_waiter_does_not_hold_up_the_line(self):
        holder = self.hold()
        doomed = self.enqueue(tag="doomed")
        survivor = self.enqueue(tag="survivor", FAKE_SLEEP="0.05")
        doomed.kill()
        self.assertEqual(holder.wait(timeout=30), 0)
        self.assertEqual(survivor.wait(timeout=30), 0)
        self.assertEqual(self.starts(), ["holder", "survivor"])

    def test_run_that_was_stopped_while_waiting_rejoins_at_its_place(self):
        holder = self.hold()
        timed_out = self.enqueue(tag="timed-out", TEST_LABEL="Repo/one")
        other = self.enqueue(tag="other", FAKE_SLEEP="0.05", TEST_LABEL="Repo/two")
        timed_out.terminate()
        timed_out.wait(timeout=5)
        again = self.start(tag="again", FAKE_SLEEP="0.05", TEST_LABEL="Repo/one")
        for child in (holder, again, other):
            self.assertEqual(child.wait(timeout=30), 0)
        self.assertEqual(self.starts(), ["holder", "again", "other"])

    def test_suspended_waiter_loses_its_turn_until_it_resumes(self):
        holder = self.hold(TEST_STALE="1")
        suspended = self.enqueue(tag="suspended", FAKE_SLEEP="0.05", TEST_STALE="1")
        awake = self.enqueue(tag="awake", FAKE_SLEEP="0.05", TEST_STALE="1")
        suspended.send_signal(signal.SIGSTOP)
        self.addCleanup(lambda: suspended.poll() is None and suspended.send_signal(signal.SIGCONT))
        self.assertEqual(holder.wait(timeout=30), 0)
        self.assertEqual(awake.wait(timeout=15), 0)
        suspended.send_signal(signal.SIGCONT)
        self.assertEqual(suspended.wait(timeout=30), 0)
        self.assertEqual(self.starts(), ["holder", "awake", "suspended"])

    def test_build_that_lost_its_supervisor_is_stopped_for_a_waiter(self):
        # ps prints start times in the caller's locale and time zone.
        orphan = self.hold(FAKE_SLEEP="60", LC_ALL="nb_NO.UTF-8", TZ="Asia/Tokyo")
        build_pid = int(self.events.read_text().split()[2])
        orphan.kill()
        orphan.wait(timeout=5)
        self.assertEqual(self.start(tag="waiter", FAKE_SLEEP="0.05", TEST_STALE="1").wait(timeout=15), 0)
        self.assertFalse(agent.process_alive(build_pid))
        self.assertEqual(self.log(), [["start", "holder"], ["start", "waiter"], ["end", "waiter"]])

    def test_run_that_stalled_while_holding_a_phone_takes_it_again(self):
        device = "device-00008150-000230D82E40401C"
        compile = self.hold(FAKE_SLEEP="5", TEST_STALE="1")
        stalled = self.start("test", "-destination", PHONE, tag="stalled", FAKE_SLEEP="0.05", TEST_STALE="1")
        self.wait_for(lambda: self.tickets(device), "the test never took the phone")
        stalled.send_signal(signal.SIGSTOP)
        self.addCleanup(lambda: stalled.poll() is None and stalled.send_signal(signal.SIGCONT))
        other = self.start("test-without-building", "-destination", PHONE, tag="other", FAKE_SLEEP="6", TEST_STALE="1")
        self.wait_for(lambda: ["start", "other"] in self.log(), "the phone was never given to the next run")
        stalled.send_signal(signal.SIGCONT)
        for child in (compile, other, stalled):
            self.assertEqual(child.wait(timeout=30), 0)
        self.assertLess(self.log().index(["end", "other"]), self.log().index(["start", "stalled"]))

    def test_stale_parent_marker_does_not_skip_the_queue(self):
        self.assertEqual(self.start(tag="earlier", FAKE_SLEEP="0.05").wait(timeout=30), 0)
        holder = self.hold()
        stale = str(self.queues / "build/000000000001")
        self.assertEqual(self.start(tag="later", FAKE_SLEEP="0.05", IOS_AGENT_HELD=stale).wait(timeout=30), 0)
        self.assertEqual(holder.wait(timeout=5), 0)
        self.assertLess(self.log().index(["end", "holder"]), self.log().index(["start", "later"]))

    def test_killed_supervisor_does_not_allow_overlapping_build(self):
        first = self.hold(FAKE_SLEEP="0.6")
        first.kill()
        first.wait(timeout=5)
        self.assertEqual(self.start(tag="second").wait(timeout=10), 0)
        self.assertEqual(self.log(), [["start", "holder"], ["end", "holder"], ["start", "second"], ["end", "second"]])

    def test_cancellation_stops_build_before_releasing_queue(self):
        child = self.hold(FAKE_SLEEP="30")
        build_pid = int(self.events.read_text().split()[2])
        child.send_signal(signal.SIGTERM)
        self.assertEqual(child.wait(timeout=5), 143)
        self.assertFalse(agent.process_alive(build_pid))
        self.assertEqual(self.tickets(), [])

    def test_prebuilt_tests_run_while_a_build_holds_the_queue(self):
        holder = self.hold()
        self.assertEqual(self.start("test-without-building", tag="tests", FAKE_SLEEP="0.05").wait(timeout=5), 0)
        self.assertEqual(self.start("build-for-testing", tag="compile", FAKE_SLEEP="0.05").wait(timeout=30), 0)
        self.assertEqual(holder.wait(timeout=5), 0)
        self.assertEqual(self.log(), [["start", "holder"], ["start", "tests"], ["end", "tests"], ["end", "holder"],
                                      ["start", "compile"], ["end", "compile"]])

    def test_nested_build_does_not_wait_for_its_own_parent(self):
        self.assertEqual(self.start(tag="outer", FAKE_NESTED="1", FAKE_SLEEP="0.05").wait(timeout=20), 0)
        self.assertEqual(self.log(), [["start", "outer"], ["start", "inner"], ["end", "inner"], ["end", "outer"]])

    def test_hold_limit_stops_a_build_only_when_others_wait(self):
        holder = self.hold(FAKE_SLEEP="30", IOS_AGENT_HOLD_LIMIT_MINUTES="0.01")
        time.sleep(1.5)
        self.assertIsNone(holder.poll(), "a build nobody waits for was stopped")
        waiter = self.enqueue(tag="waiter", FAKE_SLEEP="0.05")
        self.assertEqual(holder.wait(timeout=20), 124)
        self.assertEqual(waiter.wait(timeout=20), 0)
        self.assertEqual(self.log(), [["start", "holder"], ["start", "waiter"], ["end", "waiter"]])

    def test_hold_limit_counts_the_run_not_the_wait(self):
        limit = {"IOS_AGENT_HOLD_LIMIT_MINUTES": "0.05"}
        self.hold(FAKE_SLEEP="4", **limit)
        queued = self.start("test", "-destination", PHONE, tag="queued", FAKE_SLEEP="1.5", **limit)
        self.wait_for(lambda: len(self.tickets()) == 2, "the test never queued for the build")
        behind = self.enqueue(tag="behind", FAKE_SLEEP="0.05", **limit)
        self.assertEqual(queued.wait(timeout=30), 0)
        self.assertEqual(behind.wait(timeout=30), 0)

    def test_one_test_run_per_phone(self):
        other = PHONE.replace("401C", "401D")
        shared = "platform=iOS Simulator,id=" + agent.SIMULATORS[0][1]
        self.hold("test-without-building", "-destination", PHONE)
        same = self.start("test-without-building", "-destination", PHONE, tag="same-phone", FAKE_SLEEP="0.05")
        for tag, destination in (("other-phone", other), ("simulator", shared)):
            self.assertEqual(self.start("test-without-building", "-destination", destination, tag=tag,
                                        FAKE_SLEEP="0.05").wait(timeout=5), 0)
        self.assertEqual(same.wait(timeout=30), 0)
        self.assertEqual(self.starts(), ["holder", "other-phone", "simulator", "same-phone"])
        self.assertLess(self.log().index(["end", "holder"]), self.log().index(["start", "same-phone"]))
        self.assertEqual(sorted(path.name for path in self.queues.iterdir()),
                         ["device-00008150-000230D82E40401C", "device-00008150-000230D82E40401D"])

    def test_phone_named_twice_is_queued_for_once(self):
        self.assertEqual(self.start("test-without-building", "-destination", PHONE, "-destination", PHONE,
                                    FAKE_SLEEP="0.05").wait(timeout=10), 0)

    def test_run_waiting_for_a_phone_does_not_hold_up_compiles(self):
        phone = self.hold("test-without-building", "-destination", PHONE)
        waiting = self.start("test", "-destination", PHONE, tag="phone-test", FAKE_SLEEP="0.05")
        self.wait_for(lambda: len(self.tickets("device-00008150-000230D82E40401C")) == 2, "the test never queued for the phone")
        self.assertEqual(self.start(tag="compile", FAKE_SLEEP="0.05").wait(timeout=5), 0)
        self.assertIsNone(phone.poll(), "the compile waited for the phone run")
        self.assertEqual(phone.wait(timeout=30), 0)
        self.assertEqual(waiting.wait(timeout=30), 0)

    def test_status_file_reports_the_wait_then_the_start(self):
        status = self.root / "status"
        holder = self.hold()
        waiter = self.enqueue("build-for-testing", tag="waiter", FAKE_SLEEP="0.05", IOS_AGENT_STATUS_FILE=str(status))
        self.wait_for(status.exists, "the waiter never reported")
        state, detail = status.read_text().rstrip("\n").split("\t")
        self.assertEqual(state, "queued")
        self.assertRegex(detail, r"^build: position 2 of 2; running now: \S+ build since \d\d:\d\d:\d\d$")
        self.assertEqual(holder.wait(timeout=30), 0)
        self.assertEqual(waiter.wait(timeout=30), 0)
        state, started = status.read_text().split()
        self.assertEqual(state, "running")
        self.assertLess(abs(time.time() - int(started)), 30)

    def test_status_lists_the_runner_then_the_waiters_in_order(self):
        self.hold("archive")
        self.enqueue("build-for-testing")
        self.enqueue("clean")
        owner = self.root / "locks/simulator/owner"
        owner.parent.mkdir(parents=True)
        owner.write_text(f"/Users/someone/worktrees/Tidex/feature||{int(time.time()) - 120}")
        (self.root / "locks/.waiting").mkdir()
        (self.root / f"locks/.waiting/{int(time.time()) - 185}-1").write_text("/Users/someone/worktrees/Paeonia/fix|simulator simulator-2")
        (self.root / f"locks/.waiting/{int(time.time()) - 400}-2.reserved").write_text("/Users/someone/worktrees/Paeonia/gone|simulator")
        document = agent.status(self.queues, self.root / "locks", self.root / "library")
        self.assertEqual([(ticket["action"], ticket["state"]) for ticket in document["queues"]["build"]],
                         [("archive", "running"), ("build-for-testing", "waiting"), ("clean", "waiting")])
        self.assertEqual(document["simulators"][0], {"name": "Shared iPhone", "holder": "Tidex/feature", "kind": "session", "minutes": 2})
        self.assertEqual(document["simulators"][1], {"name": "Shared iPhone 2", "holder": None})
        self.assertEqual(document["simulator_waiters"],
                         [{"label": "Paeonia/fix", "wants": ["Shared iPhone", "Shared iPhone 2"], "minutes": 3}])
        self.assertFalse(document["controller"]["current"])

    def test_status_answers_while_a_stuck_process_holds_the_line(self):
        self.assertEqual(self.start(FAKE_SLEEP="0.05").wait(timeout=30), 0)
        with (self.queues / "build/guard").open("a") as guard:
            fcntl.flock(guard, fcntl.LOCK_EX)
            document = agent.status(self.queues, self.root / "locks", self.root / "library")
        self.assertIsNone(document["queues"]["build"])


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.repo = self.root / "repo"
        self.script = self.repo / "scripts/ios-agent"
        self.script.parent.mkdir(parents=True)
        self.script.write_bytes(SOURCE.read_bytes())
        self.script.with_name("test-ios-agent.py").write_text("")
        self.git("init", "-q", "-b", "main")
        self.commit("first")
        self.installed = self.home / ".local/lib/ios-agent/ios-agent"

    def git(self, *arguments):
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        return subprocess.run(["/usr/bin/git", "-C", str(self.repo), "-c", "commit.gpgsign=false", "-c", "user.name=test",
                               "-c", "user.email=test@example.com", *arguments],
                              capture_output=True, text=True, check=True, env=environment).stdout.strip()

    def commit(self, message):
        self.git("add", "scripts")
        self.git("commit", "-q", "-m", message)

    def edit(self):
        with self.script.open("a") as script:
            script.write("# edited\n")

    def installer(self, checks="true", replace=False, **environment):
        code = f"""import runpy, sys
m = runpy.run_path({str(self.script)!r}, run_name="ios_agent_test")
try:
    m["install_user"]({str(self.home)!r}, False, {checks.split()!r}, {replace!r})
except ValueError as error:
    sys.exit(str(error))
"""
        return subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                env=dict(os.environ, **environment))

    def install(self, *arguments, **options):
        process = self.installer(*arguments, **options)
        output, errors = process.communicate(timeout=60)
        return subprocess.CompletedProcess(process.args, process.returncode, output, errors)

    def controller(self):
        return agent.status(self.root / "queues", self.root / "locks", self.installed.parent)["controller"]

    def test_installs_what_main_commits_and_records_where_it_came_from(self):
        first = self.script.read_bytes()
        self.edit()
        # A git hook exports these, and the working copy is ahead of the commit.
        result = self.install(GIT_DIR=str(self.root / "elsewhere"), GIT_INDEX_FILE=str(self.root / "elsewhere/index"))
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertEqual(self.installed.read_bytes(), first)
        self.assertIn(str(self.installed), (self.home / ".local/bin/ios-agent").read_text())
        controller = self.controller()
        self.assertEqual((Path(controller["repo"]).resolve(), controller["commit"], controller["current"]),
                         (self.repo.resolve(), self.git("rev-parse", "HEAD"), True))
        self.commit("newer")
        self.assertFalse(self.controller()["current"])

    def test_current_copy_needs_no_checks_from_any_branch(self):
        self.install()
        self.git("checkout", "-q", "-b", "feature")
        self.assertEqual(self.install(checks="false").returncode, 0)

    def test_refuses_a_copy_that_could_be_older_or_broken(self):
        self.install()
        first = self.installed.read_bytes()
        self.edit()
        self.commit("second")
        failing = self.install(checks="false")
        self.git("checkout", "-q", "-b", "feature")
        branch = self.install()
        self.assertEqual(self.installed.read_bytes(), first)
        self.git("checkout", "-q", "main")
        self.assertEqual(self.install().returncode, 0)
        second = self.installed.read_bytes()
        self.assertNotEqual(second, first)
        self.git("reset", "-q", "--hard", "HEAD~1")
        self.git("commit", "-q", "--allow-empty", "-m", "rewound")
        older = self.install()
        for result in (failing, branch, older):
            self.assertIn("refusing to install", result.stderr)
            self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installed.read_bytes(), second)
        self.assertEqual(self.install(replace=True).returncode, 0)
        self.assertEqual(self.installed.read_bytes(), first)

    def test_rewritten_commit_does_not_lock_out_later_installs(self):
        self.edit()
        self.commit("second")
        self.install()
        self.git("commit", "-q", "--amend", "-m", "second, reworded")
        self.edit()
        self.commit("third")
        result = self.install()
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertEqual(self.installed.read_bytes(), self.script.read_bytes())

    def test_slow_install_does_not_finish_over_a_newer_one(self):
        self.install()
        self.edit()
        self.commit("second")
        slow = self.installer(checks="sleep 2")
        time.sleep(1)
        self.edit()
        self.commit("third")
        self.assertEqual(self.install().returncode, 0)
        slow.communicate(timeout=30)
        self.assertEqual(slow.returncode, 0)
        self.assertEqual(self.installed.read_bytes(), self.script.read_bytes())


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
            with mock.patch.object(agent, "memory_tight", return_value=True):
                self.assertEqual(self.shutdowns(lease_root, devices), [agent.SIMULATORS[1][1], agent.SIMULATORS[2][1]])
                owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
                self.assertEqual(self.shutdowns(lease_root, devices), [agent.SIMULATORS[2][1]])
            owner.parent.rename(owners / "released")
            owner.parent.mkdir()
            owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
            self.assertFalse(agent.simulator_reserved(agent.SIMULATORS[1][1], lease_root))

    def shutdowns(self, lease_root, devices):
        with mock.patch.object(agent.subprocess, "run", return_value=mock.Mock(stdout=json.dumps(devices))) as run:
            agent.enforce_simulators(lease_root)
            return [call.args[0][-1] for call in run.call_args_list if "shutdown" in call.args[0]]

    def test_a_released_extra_stays_booted_for_the_warm_period(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            owners = root / "locks"
            lease_root = root / "leases"
            owner = owners / "simulator-2/owner"
            owner.parent.mkdir(parents=True)
            owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
            agent.grant_simulator("Shared iPhone 2", lease_root, owners)
            name, udid = agent.SIMULATORS[1]
            devices = {"devices": {"runtime": [{"name": name, "udid": udid, "state": "Booted"}]}}
            idle = lease_root / f"{udid}.idle"

            def age(seconds):
                os.utime(idle, (time.time() - seconds,) * 2)

            with mock.patch.object(agent, "memory_tight", return_value=False):
                owner.unlink()
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                age(agent.WARM - 30)
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                # The next agent takes it within the period, so a later release starts a new one.
                owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                owner.unlink()
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                # So does one that takes and releases it between two checks.
                age(agent.WARM)
                owner.write_text(f"checkout|{os.getpid()}|{int(time.time())}")
                agent.grant_simulator("Shared iPhone 2", lease_root, owners)
                owner.unlink()
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                age(agent.WARM - 30)
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                age(agent.WARM)
                self.assertEqual(self.shutdowns(lease_root, devices), [udid])
                # A simulator that something else shut down starts a new period at its next release.
                self.assertEqual(self.shutdowns(lease_root, devices), [])
                age(agent.WARM)
                self.assertEqual(self.shutdowns(lease_root, {"devices": {}}), [])
                self.assertEqual(self.shutdowns(lease_root, devices), [])
            with mock.patch.object(agent, "memory_tight", return_value=True):
                self.assertEqual(self.shutdowns(lease_root, devices), [udid])


if __name__ == "__main__":
    unittest.main()
