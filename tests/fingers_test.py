#!/usr/bin/python3
"""python3 tests/fingers_test.py -- the finger reader's decoding, on synthetic events and a fake sysfs/udev tree."""
import importlib.machinery
import importlib.util
import os
import pathlib
import shutil
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True


def load_reader():
    loader = importlib.machinery.SourceFileLoader("tactile_fingers", str(ROOT / "bin" / "tactile-fingers"))
    spec = importlib.util.spec_from_loader("tactile_fingers", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


F = load_reader()
RANGES = {F.ABS_MT_POSITION_X: (0, 1000, 10, 0), F.ABS_MT_POSITION_Y: (0, 500, 10, 0), F.ABS_MT_PRESSURE: (0, 255, 0, 0)}


def feed(state, events):
    frames = []
    for etype, code, value in events:
        if state.feed(etype, code, value):
            frames.append(state.frame())
    return frames


class Decoding(unittest.TestCase):
    def test_event_layout_is_the_kernels(self):
        self.assertEqual((F.EVENT.size, F.ABSINFO.size), (24, 24))
        self.assertEqual((F.eviocgabs(F.ABS_MT_POSITION_X), F.eviocgname(256)), (0x80184575, 0x81004506))

    def test_fingers_land_move_and_lift(self):
        s = F.Fingers(RANGES)
        frames = feed(s, [
            (F.EV_ABS, F.ABS_MT_SLOT, 0), (F.EV_ABS, F.ABS_MT_TRACKING_ID, 7), (F.EV_ABS, F.ABS_MT_POSITION_X, 500),
            (F.EV_ABS, F.ABS_MT_POSITION_Y, 125), (F.EV_ABS, F.ABS_MT_PRESSURE, 51), (F.EV_KEY, 0x145, 1), (F.EV_SYN, F.SYN_REPORT, 0),
            (F.EV_ABS, F.ABS_MT_SLOT, 1), (F.EV_ABS, F.ABS_MT_TRACKING_ID, 8), (F.EV_ABS, F.ABS_MT_POSITION_X, 2000),
            (F.EV_ABS, F.ABS_MT_POSITION_Y, 500), (F.EV_KEY, 0x145, 0), (F.EV_KEY, 0x14D, 1), (F.EV_SYN, F.SYN_REPORT, 0),
            (F.EV_ABS, F.ABS_MT_SLOT, 0), (F.EV_ABS, F.ABS_MT_TRACKING_ID, -1), (F.EV_KEY, 0x14D, 0), (F.EV_KEY, 0x145, 1),
            (F.EV_SYN, F.SYN_REPORT, 0),
        ])
        self.assertEqual(frames[0], {"fingers": [{"slot": 0, "x": 0.5, "y": 0.25, "p": 0.2}], "count": 1, "button": False})
        self.assertEqual(frames[1]["count"], 2)
        self.assertEqual(frames[1]["fingers"][1], {"slot": 1, "x": 1.0, "y": 1.0, "p": None}, "positions are clamped")
        self.assertEqual(frames[2], {"fingers": [{"slot": 1, "x": 1.0, "y": 1.0, "p": None}], "count": 1, "button": False})

    def test_positions_stick_until_changed_and_bad_slots_are_ignored(self):
        s = F.Fingers(RANGES)
        feed(s, [(F.EV_ABS, F.ABS_MT_TRACKING_ID, 1), (F.EV_ABS, F.ABS_MT_POSITION_X, 100), (F.EV_ABS, F.ABS_MT_POSITION_Y, 100),
                 (F.EV_SYN, F.SYN_REPORT, 0)])
        frames = feed(s, [(F.EV_ABS, F.ABS_MT_POSITION_X, 300), (F.EV_KEY, F.BTN_LEFT, 1), (F.EV_SYN, F.SYN_REPORT, 0),
                          (F.EV_ABS, F.ABS_MT_SLOT, 99), (F.EV_ABS, F.ABS_MT_TRACKING_ID, 5), (F.EV_SYN, F.SYN_REPORT, 0)])
        self.assertEqual(frames[0], {"fingers": [{"slot": 0, "x": 0.3, "y": 0.2, "p": None}], "count": 1, "button": True})
        self.assertEqual(frames[1]["fingers"], frames[0]["fingers"])

    def test_dropped_events_clear_the_slots(self):
        s = F.Fingers(RANGES)
        frames = feed(s, [(F.EV_ABS, F.ABS_MT_TRACKING_ID, 1), (F.EV_ABS, F.ABS_MT_POSITION_X, 1), (F.EV_ABS, F.ABS_MT_POSITION_Y, 1),
                          (F.EV_SYN, F.SYN_DROPPED, 0), (F.EV_SYN, F.SYN_REPORT, 0)])
        self.assertEqual(frames, [{"fingers": [], "count": 0, "button": False}])


class Discovery(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="tactile-fingers-test-"))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def device(self, name, dev, udev_lines):
        (self.root / "sys" / name).mkdir(parents=True)
        (self.root / "sys" / name / "dev").write_text(dev + "\n")
        (self.root / "udev").mkdir(exist_ok=True)
        (self.root / "udev" / ("c" + dev)).write_text("\n".join(udev_lines) + "\n")

    def test_finds_the_touchpad_by_udev_property(self):
        self.device("event3", "13:67", ["E:ID_INPUT=1", "E:ID_INPUT_KEYBOARD=1"])
        self.device("event12", "13:76", ["E:ID_INPUT=1", "E:ID_INPUT_TOUCHPAD=1"])
        self.device("event8", "13:72", ["E:ID_INPUT=1", "E:ID_INPUT_TOUCHPAD=1"])
        (self.root / "sys" / "mouse0").mkdir()
        self.assertEqual(F.find_touchpad(str(self.root / "sys"), str(self.root / "udev")), "/dev/input/event8")

    def test_no_touchpad(self):
        self.device("event3", "13:67", ["E:ID_INPUT_TOUCHPAD=0"])
        self.assertIsNone(F.find_touchpad(str(self.root / "sys"), str(self.root / "udev")))
        self.assertIsNone(F.find_touchpad(str(self.root / "missing"), str(self.root / "udev")))


if __name__ == "__main__":
    unittest.main(verbosity=1)
