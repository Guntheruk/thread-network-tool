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

    def test_preparation_diagnostics_only_emit_fixed_stage_and_reason(self):
        reader, writer = os.pipe()
        try:
            os.write(writer, b"TNT_APP_PREPARE_FAILURE native_result source_snapshot_changed_or_unavailable\n"
                     b"TNT_APP_PREPARE_FAILURE private_stage invalid_request\n"
                     b"TNT_APP_PREPARE_FAILURE native_result private_error_data\n"
                     b"TNT_APP_PREPARE_FAILURE native_result invalid_request_extra\n"
                     b"private data\n")
        finally:
            os.close(writer)
        output = io.StringIO()
        with os.fdopen(reader, "rb") as stream, contextlib.redirect_stdout(output):
            fixture.drain_events(stream, "dispatch", {})
        rows = [__import__("json").loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(rows, [{"lab": "app-execution-bridge", "app_phase": "dispatch",
                                "preparation_failure_stage": "native_result",
                                "preparation_failure_reason": "source_snapshot_changed_or_unavailable"}])
        self.assertNotIn("private", output.getvalue())

    def test_execution_guard_marker_does_not_export_guard_details(self):
        output, marks = io.StringIO(), {}
        with contextlib.redirect_stdout(output):
            fixture.emit_fixed_line(b"TNT_APP_EVENT execution_guard_blocked", "dispatch", marks)
            fixture.emit_fixed_line(b"TNT_APP_EVENT execution_guard_blocked_private", "dispatch", marks)
        rows = [__import__("json").loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(rows, [{"lab": "app-execution-bridge", "app_phase": "dispatch",
                                "app_event": "execution_guard_blocked"}])
        self.assertEqual(marks, {"dispatch": "execution_guard_blocked"})

    def test_preparation_reason_allowlist_matches_dart_boundary(self):
        source = (ROOT / "app/lib/native/native_move_diagnostic.dart").read_text()
        block = source.split("const nativePreparationReasons = {", 1)[1].split("};", 1)[0]
        reasons = set(__import__("re").findall(r"'([a-z_]+)'", block))
        self.assertEqual(reasons, fixture.PREPARATION_REASONS)

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

    def test_one_shot_ping_treats_only_pinned_transient_failure_as_false(self):
        class Node:
            def __init__(self, error=None):
                self.error = error
                self.calls = []

            def cmd(self, command):
                self.calls.append(command)
                if self.error:
                    raise self.error
                return "ping response\nDone\n"

            def read(self, pattern, timeout):
                self.calls.append(timeout)
                raise TimeoutError()

        address = "fd00::1"
        no_route = Node(fixture.reads.LabError("simulator_command", "unknown", 4))
        self.assertFalse(fixture.ping_once(no_route, address))
        self.assertEqual(len(no_route.calls), 1)
        timed_out = Node()
        self.assertFalse(fixture.ping_once(timed_out, address))
        self.assertLessEqual(timed_out.calls[-1], 3)
        unexpected = Node(fixture.reads.LabError("simulator_command", "unknown", 5))
        with self.assertRaises(fixture.reads.LabError):
            fixture.ping_once(unexpected, address)
        async_error = Node()
        async_error.read = lambda pattern, timeout: "Error 4: NoRoute\n"
        self.assertFalse(fixture.ping_once(async_error, address))
        async_unexpected = Node()
        async_unexpected.read = lambda pattern, timeout: "Error 5: Busy\n"
        with self.assertRaises(fixture.reads.LabError):
            fixture.ping_once(async_unexpected, address)
        verified = Node()
        verified.read = lambda pattern, timeout: "8 bytes from fd00::1: icmp_seq=1\n"
        self.assertTrue(fixture.ping_once(verified, address))
        wrong_peer = Node()
        wrong_peer.read = lambda pattern, timeout: "8 bytes from fd00::2: icmp_seq=1\n"
        self.assertFalse(fixture.ping_once(wrong_peer, address))

    def test_disconnected_client_does_not_stop_control_handler(self):
        class Connection:
            def __init__(self):
                self.sent = 0

            def recv(self, size):
                return b'{"action":"metrics"}\n'

            def sendall(self, response):
                self.sent += 1
                raise BrokenPipeError()

        class Service:
            def response(self, action):
                return {"ok": True, "action": action}

        connection = Connection()
        fixture.handle_connection(connection, Service())
        self.assertEqual(connection.sent, 1)
        # A later request still reaches the same coordinator object.
        next_connection = Connection()
        fixture.handle_connection(next_connection, Service())
        self.assertEqual(next_connection.sent, 1)

    def test_real_unix_client_close_survives_and_later_request_works(self):
        class Service:
            calls = 0

            def response(self, action):
                self.calls += 1
                return {"ok": True}

        service = Service()
        server, client = socket.socketpair(socket.AF_UNIX)
        try:
            client.sendall(b'{"action":"refresh"}\n')
            client.close()
            fixture.handle_connection(server, service)
        finally:
            server.close()
            client.close()
        server, client = socket.socketpair(socket.AF_UNIX)
        try:
            client.sendall(b'{"action":"metrics"}\n')
            fixture.handle_connection(server, service)
            self.assertEqual(client.recv(128), b'{"ok":true}\n')
        finally:
            server.close()
            client.close()
        self.assertEqual(service.calls, 2)

    def test_failure_report_redacts_context_and_bounds_cli_code(self):
        item = fixture.Fixture("key-change-older-target")
        item.refresh_stage = "connectivity"
        error = fixture.reads.LabError("simulator_command", "secret dataset", 4)
        report = fixture.failure_report(item, "app", error)
        self.assertEqual(report["error_code"], "simulator_command")
        self.assertEqual(report["refresh_stage"], "connectivity")
        self.assertEqual(report["cli_error_code"], 4)
        self.assertNotIn("secret", __import__("json").dumps(report))
        error = fixture.reads.LabError("secret dataset", "secret dataset", 999999)
        report = fixture.failure_report(item, "app", error)
        self.assertEqual(report["error_code"], "fixture_error")
        self.assertNotIn("cli_error_code", report)
        self.assertNotIn("secret", __import__("json").dumps(report))

    def test_terminal_oracle_projection_keeps_only_seven_booleans_and_freshness(self):
        item = fixture.Fixture("key-change-older-target")
        item.refresh_count = 31
        item.last = {"source_full_match_target": True, "target_unchanged": True,
                     "source_no_pending": False, "target_no_pending": True,
                     "same_partition": True, "source_router_roles": True,
                     "connectivity_verified": False, "connectivity_checked_at_ms": 1000,
                     "ports": [1111, 2222, 3333], "secret": "private dataset"}
        projection = fixture.oracle_summary(item, now_ms=2000)
        self.assertEqual(projection["sample_count"], 31)
        self.assertEqual(projection["sample_age_ms"], 1000)
        self.assertFalse(projection["source_no_pending"])
        self.assertFalse(projection["connectivity_verified"])
        self.assertEqual(set(projection), {"sample_count", "sample_age_ms", "sample_fresh",
                                          "source_full_match_target", "target_unchanged",
                                          "source_no_pending", "target_no_pending",
                                          "same_partition", "source_router_roles",
                                          "connectivity_verified"})
        self.assertNotIn("private", __import__("json").dumps(projection))
        item.last["source_full_match_target"] = "true"
        self.assertIsNone(fixture.oracle_summary(item, now_ms=2000)["source_full_match_target"])

    def test_fixed_app_outcome_marker_drops_unknown_fields(self):
        output = io.StringIO()
        events, outcomes = {}, {}
        with contextlib.redirect_stdout(output):
            fixture.emit_fixed_line(
                b"TNT_APP_OUTCOME needs_attention verification_failed observer_or_evidence_failure",
                "recover", events, outcomes)
            fixture.emit_fixed_line(
                b"TNT_APP_OUTCOME private_stage verification_failed observer_or_evidence_failure",
                "recover", events, outcomes)
            fixture.emit_fixed_line(
                b"TNT_APP_OUTCOME needs_attention private_reason observer_or_evidence_failure",
                "recover", events, outcomes)
        self.assertEqual(outcomes, {"recover": {"stage": "needs_attention",
                                                "reason": "verification_failed",
                                                "category": "observer_or_evidence_failure"}})
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertNotIn("private", output.getvalue())

    def test_failed_app_terminal_report_keeps_nonzero_exit_and_sanitized_evidence(self):
        item = fixture.Fixture("key-change-older-target")
        item.refresh_count = 4
        item.last = {"source_full_match_target": False, "private": "raw address"}
        item.app_outcomes["recover"] = {"stage": "observing",
                                        "reason": "verification_pending",
                                        "category": "oracle_incomplete", "private": "raw address"}
        report = fixture.app_result(item, 1, 2, "recover", "observing", now_ms=1000)
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["app_exit_code"], 1)
        self.assertEqual(report["last_app_outcome"]["category"], "oracle_incomplete")
        self.assertEqual(set(report["last_app_outcome"]), {"stage", "reason", "category"})
        self.assertFalse(report["oracle"]["source_full_match_target"])
        self.assertNotIn("raw address", __import__("json").dumps(report))
        item.app_outcomes["recover"]["category"] = "raw address"
        self.assertIsNone(fixture.app_result(item, 1, 2, "recover", "observing")["last_app_outcome"])


if __name__ == "__main__":
    unittest.main()
