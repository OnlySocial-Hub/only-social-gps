"""NDJSON framing and request/reply semantics of the hub, run as a real subprocess with USB
discovery disabled (OSGPS_NO_USB=1). No hardware needed; pymobiledevice3 need not be importable.
"""

import json
import os
import subprocess
import sys
import time
import unittest

ENGINE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE = os.path.join(ENGINE_DIR, "osgps_engine.py")
sys.path.insert(0, ENGINE_DIR)

import osgps_engine as eng  # noqa: E402


def run_hub(requests, timeout=30, close_stdin=True):
    """Feed NDJSON requests, return (exit_code, list_of_parsed_stdout_objects, stderr_text)."""
    env = dict(os.environ, OSGPS_NO_USB="1", PYTHONUNBUFFERED="1")
    payload = "".join(json.dumps(r) + "\n" for r in requests)
    proc = subprocess.run([sys.executable, ENGINE], input=payload.encode(), capture_output=True,
                          timeout=timeout, env=env)
    lines = [ln for ln in proc.stdout.decode("utf-8").split("\n") if ln.strip()]
    objs = []
    for ln in lines:
        objs.append(json.loads(ln))  # every stdout line must be valid JSON
    return proc.returncode, objs, proc.stderr.decode("utf-8", "replace")


class FramingTests(unittest.TestCase):
    def test_hello_first_then_devices_and_exit_on_eof(self):
        rc, objs, err = run_hub([])
        self.assertEqual(rc, 0, err)
        self.assertEqual(objs[0]["event"], "hello")
        self.assertEqual(objs[0]["engine_version"], "1.0")
        self.assertIsInstance(objs[0]["pid"], int)
        self.assertTrue(any(o.get("event") == "devices" for o in objs))

    def test_every_request_gets_exactly_one_reply(self):
        reqs = [
            {"id": 1, "cmd": "hello", "app_version": "1.0"},
            {"id": "two", "cmd": "list_devices"},
            {"id": 3, "cmd": "parse_proxy", "proxy": "1.2.3.4:1080:alice:s3cret"},
            {"id": 4, "cmd": "parse_proxy", "proxy": "nope"},
            {"id": 5, "cmd": "no_such_cmd"},
            {"id": 6, "cmd": "set_desired", "udid": "FAKE", "target": {"lat": 51.5, "lon": -0.12}},
            {"id": 7, "cmd": "worker_status"},
            {"id": 8, "cmd": "set_desired", "udid": "FAKE", "target": {"lat": 999, "lon": 0}},
            {"id": 9, "cmd": "release_all"},
            {"id": 10, "cmd": "set_all", "targets": {"FAKE": {"lat": 1, "lon": 2}, "OTHER": None}},
            {"id": 11, "cmd": "shutdown"},
        ]
        rc, objs, err = run_hub(reqs)
        self.assertEqual(rc, 0, err)
        replies = {o["id"]: o for o in objs if "ok" in o}
        self.assertEqual(sorted(replies, key=str), sorted([r["id"] for r in reqs], key=str))
        for r in reqs:
            n = sum(1 for o in objs if "ok" in o and o["id"] == r["id"])
            self.assertEqual(n, 1, f"request {r['id']} got {n} replies")
        self.assertTrue(replies[1]["ok"])
        self.assertEqual(replies[1]["result"]["engine_version"], "1.0")
        self.assertIn("capabilities", replies[1]["result"])
        self.assertTrue(replies["two"]["ok"])
        self.assertEqual(replies["two"]["result"]["devices"], [])
        self.assertTrue(replies[3]["ok"])
        self.assertEqual(replies[3]["result"]["normalized"], "socks5h://alice:***@1.2.3.4:1080")
        self.assertFalse(replies[4]["ok"])
        self.assertEqual(replies[4]["error"]["code"], "parse_error")
        self.assertFalse(replies[5]["ok"])
        self.assertEqual(replies[5]["error"]["code"], "unknown_command")
        self.assertTrue(replies[6]["ok"])
        self.assertEqual(replies[6]["result"], {"accepted": True})
        self.assertTrue(replies[7]["ok"])
        self.assertEqual(replies[7]["result"]["workers"]["FAKE"]["state"], "disconnected")
        self.assertEqual(replies[7]["result"]["workers"]["FAKE"]["pid"], None)
        self.assertFalse(replies[8]["ok"])
        self.assertEqual(replies[8]["error"]["code"], "bad_request")
        self.assertTrue(replies[9]["ok"])
        self.assertEqual(replies[9]["result"]["accepted"], ["FAKE"])
        self.assertTrue(replies[10]["ok"])
        self.assertEqual(sorted(replies[10]["result"]["accepted"]), ["FAKE", "OTHER"])
        self.assertEqual(replies[11]["result"], {"accepted": True})
        # a disconnected phone with a target produces a device_state event
        states = [o for o in objs if o.get("event") == "device_state" and o.get("udid") == "FAKE"]
        self.assertTrue(states)
        self.assertEqual(states[0]["state"], "disconnected")
        self.assertEqual(states[0]["target"], {"lat": 51.5, "lon": -0.12})

    def test_garbage_lines_do_not_kill_the_hub(self):
        env = dict(os.environ, OSGPS_NO_USB="1", PYTHONUNBUFFERED="1")
        payload = b'this is not json\n[1,2,3]\n{"id":1,"cmd":"hello"}\n\n{"id":2,"cmd":"shutdown"}\n'
        proc = subprocess.run([sys.executable, ENGINE], input=payload, capture_output=True, timeout=30, env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        objs = [json.loads(ln) for ln in proc.stdout.decode().split("\n") if ln.strip()]
        self.assertTrue(any(o.get("id") == 1 and o.get("ok") for o in objs))
        self.assertTrue(any(o.get("id") == 2 and o.get("ok") for o in objs))

    def test_stdout_is_pure_ndjson_even_with_stray_prints(self):
        # ProtoOut points fd 1 at stderr; a print() must not reach the protocol stream.
        code = (
            "import sys; sys.path.insert(0, %r); import osgps_engine as e; out = e.ProtoOut(); "
            "print('STRAY'); sys.stdout.flush(); out.send({'a': 1}); out.send({'b': 'ü'})"
        ) % ENGINE_DIR
        proc = subprocess.run([sys.executable, "-c", code], capture_output=True, timeout=20)
        self.assertEqual(proc.stdout, b'{"a":1}\n{"b":"\xc3\xbc"}\n')
        self.assertIn(b"STRAY", proc.stderr)

    def test_stdin_closed_immediately_exits_zero_quickly(self):
        env = dict(os.environ, OSGPS_NO_USB="1")
        t0 = time.time()
        proc = subprocess.run([sys.executable, ENGINE], stdin=subprocess.DEVNULL, capture_output=True,
                              timeout=30, env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertLess(time.time() - t0, 10)
        first = json.loads(proc.stdout.decode().split("\n")[0])
        self.assertEqual(first["event"], "hello")


class HelperTests(unittest.TestCase):
    def test_marketing_names(self):
        self.assertEqual(eng.marketing_name("iPhone11,8"), "iPhone XR")
        self.assertEqual(eng.marketing_name("iPhone12,1"), "iPhone 11")
        self.assertEqual(eng.marketing_name("iPhone17,5"), "iPhone 16e")
        self.assertEqual(eng.marketing_name("iPhone18,9"), "iPhone 17 family")
        self.assertEqual(eng.marketing_name("iPad13,1"), "iPad13,1")
        self.assertIsNone(eng.marketing_name(None))

    def test_valid_target(self):
        self.assertIsNone(eng.valid_target(None))
        self.assertEqual(eng.valid_target({"lat": "44.5", "lon": -63}), {"lat": 44.5, "lon": -63.0})
        for bad in ({"lat": 91, "lon": 0}, {"lat": 0, "lon": -181}, {"lat": "x", "lon": 0}, {"lon": 0}, 5, "str"):
            with self.assertRaises(ValueError):
                eng.valid_target(bad)


if __name__ == "__main__":
    unittest.main()
