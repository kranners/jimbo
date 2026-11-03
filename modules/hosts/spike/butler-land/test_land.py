"""A dry run of the landing queue, with a fake clock, call and commands.

Run with `python3 test_land.py`; the flake check `land-queue` runs it.
"""

import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
work = tempfile.mkdtemp()
said = os.path.join(work, "said")
open(said, "w").close()


def fake(name):
    path = os.path.join(work, name)
    with open(path, "w") as f:
        f.write(f'#!/bin/sh\n{{ printf "{name} %s|" "$*"; cat; echo; }} >> {said}\n')
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
    return path


os.environ.update(
    LAND_STATE=os.path.join(work, "state"),
    LAND_CALL_STATE=os.path.join(work, "call.json"),
    LAND_SAY=fake("say"),
    LAND_NOTIFY=fake("notify"),
    LAND_START=fake("start"),
    LAND_CUE_WAIT_S="0.2",
    LAND_POLL_S="0",
)
os.makedirs(os.environ["LAND_STATE"])
spec = importlib.util.spec_from_file_location("land", os.path.join(HERE, "land.py"))
land = importlib.util.module_from_spec(spec)
spec.loader.exec_module(land)

T0 = 1_800_000_000.0
clock = [T0]
land.now = lambda: clock[0]
commits = os.path.join(work, "commits")
with open(commits, "w") as f:
    f.write(f"abcdef1234\t{int(T0) - 60}\tGive butler a weather command\n")


def call(live=True, quiet_since=None, **flags):
    state = {
        "live": live,
        "threadId": "t",
        "callerSpeaking": False,
        "butlerSpeaking": False,
        "audioPlaying": False,
        "working": False,
        "lastActiveAt": (quiet_since if quiet_since is not None else clock[0]) * 1000,
        "lastCallerAt": None,
        "updatedAt": clock[0] * 1000,
    }
    state.update(flags)
    with open(os.environ["LAND_CALL_STATE"], "w") as f:
        json.dump(state, f)


def no_call():
    try:
        os.remove(os.environ["LAND_CALL_STATE"])
    except FileNotFoundError:
        pass


def gate(restarts="butler.service", to="bbb", urgent=""):
    return land.gate(["jimbo", "aaa", to, commits, restarts, urgent])


def heard():
    try:
        with open(said) as f:
            return f.read()
    finally:
        open(said, "w").close()


def events():
    with open(os.path.join(os.environ["LAND_STATE"], "log.jsonl")) as f:
        return [json.loads(line)["event"] for line in f]


class LandingQueue(unittest.TestCase):
    def setUp(self):
        clock[0] = T0
        for name in ("queue.json", "settings.json", "log.jsonl"):
            try:
                os.remove(os.path.join(os.environ["LAND_STATE"], name))
            except FileNotFoundError:
                pass
        no_call()
        heard()

    def test_no_call_goes_at_once(self):
        self.assertEqual(gate(), 0)
        self.assertEqual(land.queue(), {})
        self.assertEqual(land.main(["", "would-hold", "jimbo"]), 0)

    def test_nothing_disruptive_goes_during_a_call(self):
        call()
        self.assertEqual(gate(restarts=""), 0)

    def test_a_call_holds_then_quiet_releases_with_a_shout(self):
        call()
        self.assertEqual(land.main(["", "would-hold", "jimbo"]), 3)
        self.assertEqual(gate(restarts="butler.service wyoming-kokoro.service"), 3)
        self.assertIn("jimbo", land.queue())
        self.assertIn("Give butler a weather command", land.status())
        clock[0] += 10
        call(quiet_since=T0)
        land.tick()
        self.assertFalse(land.queue()["jimbo"].get("released"))
        clock[0] += 15
        call(quiet_since=T0)
        land.tick()
        out = heard()
        self.assertIn("say --urgent --call-only|" + land.CUE_LINE, out)
        self.assertIn("start jimbo-switch.service", out)
        self.assertTrue(land.queue()["jimbo"]["released"])
        # The unit runs again and its gate lets it through.
        self.assertEqual(gate(restarts="butler.service wyoming-kokoro.service"), 0)
        land.landed(["jimbo", "bbb"])
        self.assertEqual(land.queue(), {})
        self.assertEqual(events(), ["hold", "cue", "release", "deploy", "landed"])

    def test_butler_alone_leaves_the_shout_to_its_own_restart(self):
        call()
        gate()
        clock[0] += 30
        call(quiet_since=T0)
        land.tick()
        out = heard()
        self.assertNotIn("say ", out)
        self.assertIn("start jimbo-switch.service", out)

    def test_never_released_while_aaron_talks(self):
        call()
        gate()
        clock[0] += 60
        call(quiet_since=T0, callerSpeaking=True)
        land.tick()
        self.assertFalse(land.queue()["jimbo"].get("released"))
        # Quiet long enough, but he stopped only a moment ago: the shout goes, the release waits.
        call(quiet_since=T0, lastCallerAt=clock[0] * 1000 - 500, lastActiveAt=T0 * 1000)
        land.tick()
        self.assertFalse(land.queue()["jimbo"].get("released"))
        self.assertIn("wait", events())

    def test_the_call_ending_releases_with_a_dm(self):
        call()
        gate()
        no_call()
        clock[0] += 5
        land.tick()
        out = heard()
        self.assertIn("notify |Landing 1 fix held back", out)
        self.assertTrue(land.queue()["jimbo"]["released"])

    def test_a_stale_call_state_is_no_call(self):
        call()
        clock[0] += 60
        self.assertEqual(gate(), 0)

    def test_longest_hold(self):
        call()
        gate()
        clock[0] += land.MAX_HOLD_S + 1
        call(butlerSpeaking=False, working=True)
        land.tick()
        self.assertTrue(land.queue()["jimbo"]["released"])
        self.assertIn("longest hold", land.queue()["jimbo"]["releasedBecause"])

    def test_hold_and_now(self):
        land.main(["", "hold"])
        self.assertEqual(gate(), 3)
        land.tick()
        self.assertFalse(land.queue()["jimbo"].get("released"))
        code, out = land.control(["now"])
        self.assertIn("Landing everything waiting now", out)
        land.tick()
        self.assertTrue(land.queue()["jimbo"]["released"])
        gate()
        land.landed(["jimbo", "bbb"])
        self.assertNotIn("nowUntil", land.settings())

    def test_now_with_nothing_waiting_makes_the_next_urgent(self):
        land.control(["now"])
        call()
        self.assertEqual(gate(), 0)

    def test_at_a_time(self):
        call()
        target = land.parse_time(land.clock(T0 + 3600), T0)
        land.control(["at", land.clock(T0 + 3600)])
        gate()
        clock[0] += land.MAX_HOLD_S + 60
        call(quiet_since=T0)
        land.tick()
        self.assertFalse(land.queue()["jimbo"].get("released"), "a set time outlasts the longest hold and the quiet cue")
        clock[0] = target + 1
        call(quiet_since=T0)
        land.tick()
        self.assertTrue(land.queue()["jimbo"]["released"])

    def test_off_and_always(self):
        land.control(["off"])
        call()
        self.assertEqual(gate(), 0)
        land.control(["always"])
        no_call()
        self.assertEqual(gate(), 3)
        land.control(["on"])
        land.tick()
        self.assertTrue(land.queue()["jimbo"]["released"])
        self.assertEqual(land.control(["bogus"])[0], 2)

    def test_urgent_skips_the_queue(self):
        call()
        self.assertEqual(gate(), 3)
        self.assertEqual(gate(restarts="wyoming-kokoro.service", urgent="it follows a commit that failed to switch"), 0)
        self.assertEqual(land.queue(), {})
        self.assertIn(land.CUE_LINE, heard())

    def test_a_newer_commit_keeps_the_held_time(self):
        call()
        gate(to="bbb")
        clock[0] += 100
        call()
        self.assertEqual(gate(to="ccc"), 3)
        self.assertEqual(land.queue()["jimbo"]["heldSince"], T0)
        self.assertEqual(land.queue()["jimbo"]["to"], "ccc")

    def test_failure_tells_aaron(self):
        land.failed(["jimbo", "bbb", "build", "Give butler a weather command"])
        self.assertIn("say |A landed fix failed to build on spike", heard())

    def test_watch_stops_once_empty(self):
        call()
        gate()
        no_call()
        self.assertEqual(land.watch(["3"]), 0)
        self.assertTrue(land.queue()["jimbo"]["released"])
        gate()
        self.assertEqual(land.watch([]), 0)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=2).result
    sys.exit(0 if result.wasSuccessful() else 1)
