import importlib.util
import contextlib
import io
import os
from pathlib import Path
import socket
import stat
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/lab/commissioner"))
spec = importlib.util.spec_from_file_location("app_fixture", ROOT / "tools/lab/commissioner/app_fixture.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class AppFixtureTests(unittest.TestCase):
    def test_setup_uses_valid_distinct_simulator_node_ids(self):
        # The pinned simulation platform rejects IDs outside 1..33 before
        # starting its CLI. Enforce that boundary at the real setup call site.
        created = []

        class SimulatorNode:
            def __init__(self, number):
                if not 1 <= number <= 33:
                    raise ValueError("invalid simulator node ID")
                created.append(number)

            def cmd(self, command):
                raise RuntimeError("dataset setup reached")

            def close(self):
                pass

        with tempfile.TemporaryDirectory() as temporary:
            item = fixture.Fixture("key-change-older-target",
                                   root=Path(temporary) / "fixture-root")
            with mock.patch.object(fixture.move, "OracleNode", SimulatorNode), \
                    mock.patch.object(fixture.os, "makedirs"):
                with self.assertRaisesRegex(RuntimeError, "dataset setup reached"):
                    item.setup()
        self.assertEqual(len(created), 3)
        self.assertEqual(len(set(created)), 3)

    def require_unix_socket(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = socket.socket(socket.AF_UNIX)
            try:
                candidate.bind(str(Path(temporary) / "test"))
            except PermissionError:
                self.skipTest("sandbox forbids Unix socket bind")
            finally:
                candidate.close()

    def test_manifest_atomic_and_private_with_exact_wire_shape(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture-root" / "fixture"
            body = ("TNT-FIXTURE/1\nfixture_id " + "a" * 64 + "\nsource_count 2\n" +
                    "source_node " + "b" * 64 + " 10 123 9999\n" +
                    "source_node " + "c" * 64 + " 11 124 9998\n" +
                    "target_node " + "d" * 64 + " 12 125 9997\n" +
                    "connectivity_checked_at_ms 123456\nconnectivity_verified yes\n"
                    "discard_set_result no\nEND\n")
            fixture.atomic_manifest(body, path)
            self.assertEqual(path.read_text(), body)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            fixture.atomic_manifest(body.replace("9999", "9996"), path)
            self.assertIn("9996", path.read_text())
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ["fixture"])

    def test_private_root_refuses_unsafe_existing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "fixture-root"
            root.mkdir(mode=0o755)
            os.chmod(root, 0o755)
            with self.assertRaisesRegex(fixture.reads.LabError, "unsafe_fixture_path"):
                fixture.private_root(root)

    def test_proc_birth_tracks_current_process(self):
        # Field 22 is the twentieth token after the closing process name.
        fake = "123 (odd ) process) " + " ".join(["0"] * 19 + ["7654321"])
        with mock.patch.object(Path, "read_text", return_value=fake):
            self.assertEqual(fixture.process_startticks(123), 7654321)

    def test_oracle_rejects_every_post_setup_write(self):
        oracle = object.__new__(fixture.move.OracleNode)
        oracle.read_only = True
        for command in ("dataset init new", "dataset set active deadbeef", "dataset mgmtsetcommand pending -x deadbeef",
                        "thread stop", "ba enable", "factoryreset"):
            with self.subTest(command=command), self.assertRaisesRegex(fixture.reads.LabError, "oracle_write_blocked"):
                oracle.cmd(command)

    def test_bootstrap_and_discovery_are_private_socket_shapes(self):
        item = fixture.Fixture("key-change-older-target")
        # Only mock the simulator observations; shape and source/target mapping stay real.
        source = {2: bytes.fromhex("0102030405060708"), 3: b"source"}
        target = {2: bytes.fromhex("0807060504030201"), 3: b"target"}
        item.source_dataset = fixture.move.encode(source)
        item.target_dataset = fixture.move.encode(target)
        item.last = {"ports": [1001, 1002, 1003]}
        with mock.patch.object(item, "refresh", return_value=item.last):
            bootstrap = item.response("bootstrap")
            self.assertEqual(bootstrap["source_node_ids"], item.node_ids[:2])
            self.assertEqual(bootstrap["delay_ms"], 300000)
            discovery = item.response("discover")
        self.assertEqual(discovery["schema_version"], 1)
        self.assertEqual(discovery["discovery_status"], "completed")
        self.assertEqual(len(discovery["routers"]), 3)
        self.assertEqual([row["network_name"] for row in discovery["routers"]], ["source", "source", "target"])
        self.assertEqual([row["fixture_node_id"] for row in discovery["routers"]], item.node_ids)
        self.assertEqual([row["port"] for row in discovery["routers"]], [1001, 1002, 1003])
        self.assertEqual(fixture.Fixture("lost-api-result").response("bootstrap")["delay_ms"], 300000)

    def test_event_drainer_only_prints_fixed_marks_and_caps_lines(self):
        reader, writer = os.pipe()
        try:
            os.write(writer, b"secret raw output\nTNT_APP_EVENT review\n" +
                     b"x" * 4097 + b" TNT_APP_EVENT opened\n" +
                     b"TNT_APP_EVENT verified_extra\nnoise TNT_APP_EVENT verified\n")
        finally:
            os.close(writer)
        marks = {}
        output = io.StringIO()
        with os.fdopen(reader, "rb") as stream, contextlib.redirect_stdout(output):
            fixture.drain_events(stream, "recover", marks)
        self.assertEqual(marks, {"recover": "verified"})
        self.assertEqual([__import__("json").loads(line)["app_event"] for line in output.getvalue().splitlines()],
                         ["review", "verified"])
        self.assertNotIn("secret", output.getvalue())

    def test_supervisor_runs_dispatch_then_recovery_with_same_fixture(self):
        self.require_unix_socket()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "fixture-root"
            fixture.private_root(root)
            target = root / "phases"
            item = fixture.Fixture("lost-api-result", root=root)
            item.refresh = mock.Mock(return_value={})
            script = ("import os,pathlib; "
                      "p=pathlib.Path(os.environ['TNT_FIXTURE_SOCKET']).parent/'phases'; "
                      "p.open('a').write(os.environ['TNT_APP_PHASE']+'\\n')")
            code, runs, phase, last_event = fixture.serve(item, [sys.executable, "-c", script])
            self.assertEqual((code, runs, phase), (0, 2, "recover"))
            self.assertIsNone(last_event)
            self.assertEqual(target.read_text().splitlines(), ["dispatch", "recover"])
            self.assertFalse((root / "control").exists())

    def test_failed_dispatch_never_launches_recovery(self):
        self.require_unix_socket()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "fixture-root"
            fixture.private_root(root)
            item = fixture.Fixture("lost-api-result", root=root)
            item.refresh = mock.Mock(return_value={})
            script = "import os,sys; sys.exit(7 if os.environ['TNT_APP_PHASE']=='dispatch' else 0)"
            self.assertEqual(fixture.serve(item, [sys.executable, "-c", script]), (7, 1, "dispatch", None))


if __name__ == "__main__":
    unittest.main()
