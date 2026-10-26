"""Disposable three-router fixture for an application-driven synthetic move.

Only setup writes reach OpenThread. Once ready, the Oracle permits reads only;
the application under test owns any subsequent network mutation.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time

import driver as reads
import move_driver as move

ROOT = Path("/tmp/app-fixture")
MANIFEST = ROOT / "fixture"
CONTROL = ROOT / "control"
MAX_REQUEST = 1024
PING_REPLY_TIMEOUT = 3
TRANSIENT_PING_ERRORS = frozenset((4, 28))  # Pinned OpenThread NoRoute, ResponseTimeout.
REFRESH_STAGES = frozenset(("process", "ports", "datasets", "states", "partitions",
                            "pending", "connectivity", "manifest"))
FIXTURE_ERROR_CODES = frozenset(("fixture_setup", "fixture_ports", "fixture_process_changed",
                                 "fixture_not_ready", "unsafe_fixture_path", "simulator_command",
                                 "simulator_exit", "missing_value", "pending_read_unknown",
                                 "output_limit", "invalid_dataset", "oracle_write_blocked"))
EVENT_PATTERN = re.compile(rb"TNT_APP_EVENT (opened|import_target|target_read|import_source|source_read|review|native_prepare|native_confirm|dispatch_complete|stopped|restored|observing|verified|redaction|execution_guard_blocked)(?![A-Za-z0-9_])")
PREPARATION_PATTERN = re.compile(rb"TNT_APP_PREPARE_FAILURE ([a-z_]+) ([a-z_]+)(?![A-Za-z0-9_])")
OUTCOME_PATTERN = re.compile(rb"TNT_APP_OUTCOME ([a-z_]+) ([a-z_]+) ([a-z_]+)(?![A-Za-z0-9_])")
OUTCOME_STAGES = frozenset(("missing", "dispatch_fenced", "observing", "needs_attention",
                            "observation_stopped", "verified_complete", "verified_unchanged",
                            "proven_not_sent"))
OUTCOME_REASONS = frozenset(("missing", "none", "worker_accepted", "worker_rejected",
                             "worker_not_sent", "worker_uncertain", "worker_failure",
                             "journal_failure", "restart_requires_reads", "credentials_required",
                             "recovery_binding_mismatch", "verification_pending", "verification_failed",
                             "verification_complete", "verification_unchanged", "observation_stopped"))
OUTCOME_CATEGORIES = frozenset(("verified", "oracle_incomplete", "oracle_unavailable",
                                "observer_or_evidence_failure", "observation_timeout",
                                "status_unavailable", "check_exception"))
ORACLE_FLAGS = ("source_full_match_target", "target_unchanged", "source_no_pending",
                "target_no_pending", "same_partition", "source_router_roles", "connectivity_verified")
PREPARATION_STAGES = {"journal", "recovery", "fixture_refresh", "native_process", "native_result", "evidence", "plan"}
PREPARATION_REASONS = {
    "journal_failure", "unresolved_operation", "fixture_unavailable", "worker_failure",
    "uncorrelated_native_result", "native_reason_unknown", "invalid_native_evidence",
    "execution_unavailable", "review_expired", "invalid_plan", "invalid_request",
    "fixture_untrusted", "connectivity_stale", "isolated_network_required",
    "fixture_process_missing", "fixture_process_invalid", "fixture_process_replaced",
    "fixture_fd_unavailable", "fixture_socket_unowned", "fixture_socket_ambiguous",
    "fixture_duplicate", "linux_fixture_required", "lease_unavailable", "lifecycle_untrusted",
    "lifecycle_unavailable", "worker_busy", "hash_failed", "binding_mismatch", "invalid_dataset",
    "unsupported_dataset_fields", "same_network", "authorization_incomplete", "endpoint_role_conflict",
    "duplicate_endpoint", "invalid_endpoint", "timestamp_rollback_without_key_change", "unsupported_delay",
    "pending_dataset_overflow", "source_snapshot_changed_or_unavailable",
    "target_snapshot_changed_or_unavailable", "preflight_deadline", "operation_consumed",
}


def emit_fixed_line(line, phase, last_event, outcomes=None):
    match = EVENT_PATTERN.search(line)
    if match:
        event = match.group(1).decode("ascii")
        last_event[phase] = event
        print(json.dumps({"lab": "app-execution-bridge", "app_phase": phase,
                          "app_event": event}, sort_keys=True), flush=True)
    diagnostic = PREPARATION_PATTERN.search(line)
    if diagnostic:
        stage, reason = (part.decode("ascii") for part in diagnostic.groups())
        if stage in PREPARATION_STAGES and reason in PREPARATION_REASONS:
            print(json.dumps({"lab": "app-execution-bridge", "app_phase": phase,
                              "preparation_failure_stage": stage,
                              "preparation_failure_reason": reason}, sort_keys=True), flush=True)
    outcome = OUTCOME_PATTERN.search(line)
    if outcome:
        stage, reason, category = (part.decode("ascii") for part in outcome.groups())
        if stage in OUTCOME_STAGES and reason in OUTCOME_REASONS and category in OUTCOME_CATEGORIES:
            fixed = {"stage": stage, "reason": reason, "category": category}
            if outcomes is not None:
                outcomes[phase] = fixed
            print(json.dumps({"lab": "app-execution-bridge", "app_phase": phase,
                              "app_outcome": fixed}, sort_keys=True), flush=True)


def drain_events(stream, phase, last_event, outcomes=None):
    """Discard all runner output except bounded fixed-vocabulary progress marks."""
    pending = b""
    dropping = False
    while True:
        block = os.read(stream.fileno(), 1024)
        if not block:
            break
        for byte in block:
            if byte == 10:
                if not dropping:
                    emit_fixed_line(pending, phase, last_event, outcomes)
                pending = b""
                dropping = False
            elif not dropping:
                if len(pending) >= 4096:
                    pending = b""
                    dropping = True
                else:
                    pending += bytes((byte,))
    if pending and not dropping:
        emit_fixed_line(pending, phase, last_event, outcomes)


def process_startticks(pid):
    """Linux proc field 22; parse after comm, which may contain spaces or ')'."""
    stat = Path(f"/proc/{pid}/stat").read_text()
    return int(stat[stat.rfind(")") + 2:].split()[19])


def ping_once(node, address):
    """A single read-only connectivity check; transient absence is false."""
    try:
        output = node.cmd("ping " + address + " 8 1")
        if re.search(r"\bbytes from " + re.escape(address) + r"\b", output):
            return True
        # The pinned CLI reports ping replies asynchronously after command Done.
        output = node.read(re.compile(r"(?:\d+ bytes from [0-9a-f:]+|1 packets received|Error \d+:)"),
                           PING_REPLY_TIMEOUT)
        error = re.search(r"Error (\d+):", output)
        if error:
            code = int(error.group(1))
            if code in TRANSIENT_PING_ERRORS:
                return False
            raise reads.LabError("simulator_command", "ping", code)
        return bool(re.search(r"\bbytes from " + re.escape(address) + r"\b", output))
    except reads.LabError as error:
        if str(error) == "simulator_command" and error.cli_error in TRANSIENT_PING_ERRORS:
            return False
        raise
    except TimeoutError:
        return False


def oracle_summary(fixture, now_ms=None):
    """Public bounded projection of the latest independent read-only sample."""
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    sample = fixture.last if isinstance(fixture.last, dict) else {}
    checked_at = sample.get("connectivity_checked_at_ms")
    age = (now_ms - checked_at if type(checked_at) is int and
           0 <= checked_at <= now_ms and now_ms - checked_at <= 1000000000 else None)
    count = fixture.refresh_count if type(fixture.refresh_count) is int and 0 <= fixture.refresh_count <= 1000000 else None
    result = {"sample_count": count, "sample_age_ms": age,
              "sample_fresh": age is not None and age <= 30000}
    for key in ORACLE_FLAGS:
        value = sample.get(key)
        result[key] = value if type(value) is bool else None
    return result


def outcome_summary(fixture, phase):
    raw = fixture.app_outcomes.get(phase)
    if not isinstance(raw, dict):
        return None
    stage, reason, category = raw.get("stage"), raw.get("reason"), raw.get("category")
    if stage not in OUTCOME_STAGES or reason not in OUTCOME_REASONS or category not in OUTCOME_CATEGORIES:
        return None
    return {"stage": stage, "reason": reason, "category": category}


def app_result(fixture, code, runs, phase, last_event, now_ms=None):
    return {"lab": "app-execution-bridge", "scenario": fixture.scenario,
            "stage": "complete" if code == 0 else phase if phase in {"dispatch", "recover"} else "unknown",
            "status": "passed" if code == 0 else "failed",
            "app_exit_code": code if type(code) is int and 0 <= code <= 255 else None,
            "app_process_runs": runs if type(runs) is int and 0 <= runs <= 2 else None,
            "last_app_phase": phase if phase in {"dispatch", "recover"} else "unknown",
            "last_app_event": last_event if last_event in {"opened", "import_target", "target_read",
                "import_source", "source_read", "review", "native_prepare", "native_confirm",
                "dispatch_complete", "stopped", "restored", "observing", "verified", "redaction",
                "execution_guard_blocked"} else None,
            "last_app_outcome": outcome_summary(fixture, phase),
            "fixture_refreshes": fixture.refresh_count if type(fixture.refresh_count) is int and
                0 <= fixture.refresh_count <= 1000000 else None,
            "oracle": oracle_summary(fixture, now_ms=now_ms)}


def failure_report(fixture, stage, error):
    code = str(error) if isinstance(error, reads.LabError) else "fixture_error"
    if isinstance(error, TimeoutError):
        code = "deadline"
    elif code not in FIXTURE_ERROR_CODES:
        code = "fixture_error"
    result = {"lab": "app-execution-bridge", "scenario": fixture.scenario,
              "stage": stage if stage in {"setup", "app"} else "unknown",
              "status": "failed", "error_code": code}
    if fixture.refresh_stage in REFRESH_STAGES:
        result["refresh_stage"] = fixture.refresh_stage
    if (isinstance(error, reads.LabError) and type(error.cli_error) is int and
            0 <= error.cli_error <= 65535):
        result["cli_error_code"] = error.cli_error
    result["last_app_outcome"] = outcome_summary(fixture, "recover")
    result["oracle"] = oracle_summary(fixture)
    return result


def handle_connection(connection, fixture):
    try:
        data = connection.recv(MAX_REQUEST + 1)
    except (BrokenPipeError, ConnectionResetError, socket.timeout):
        return
    try:
        if len(data) > MAX_REQUEST or not data.endswith(b"\n"):
            raise ValueError()
        request = json.loads(data)
        if type(request) is not dict or type(request.get("action")) is not str:
            raise ValueError()
        result = fixture.response(request["action"])
    except (ValueError, UnicodeError):
        result = {"ok": False, "error": "invalid_request"}
    try:
        connection.sendall((json.dumps(result, separators=(",", ":")) + "\n").encode())
    except (BrokenPipeError, ConnectionResetError, socket.timeout):
        # A caller that left while a read was in progress cannot stop the fixture.
        return


def private_root(root=ROOT):
    if root.is_symlink():
        raise reads.LabError("unsafe_fixture_path")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
        raise reads.LabError("unsafe_fixture_path")


def atomic_manifest(body, path=MANIFEST):
    private_root(path.parent)
    temporary = path.with_name(path.name + "." + secrets.token_hex(8))
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="ascii") as stream:
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class Fixture:
    def __init__(self, scenario, root=ROOT):
        if scenario not in {"key-change-older-target", "lost-api-result"}:
            raise ValueError("scenario")
        self.scenario = scenario
        self.root = root
        self.nodes = []
        self.fixture_id = secrets.token_hex(32)
        self.node_ids = [secrets.token_hex(32) for _ in range(3)]
        self.births = []
        self.source_dataset = None
        self.target_dataset = None
        self.refresh_count = 0
        self.read_count = 0
        self.last = None
        self.refresh_stage = None
        self.app_outcomes = {}

    def setup(self):
        private_root(self.root)
        for name in ("lifecycle", "journal"):
            private_root(self.root / name)
        # The pinned simulator accepts only IDs 1..33. Concurrent fixtures have
        # separate network namespaces, so their numeric node IDs cannot collide.
        try:
            for number in (1, 2, 3):
                os.makedirs("/tmp/node" + str(number), mode=0o700, exist_ok=True)
                self.nodes.append(move.OracleNode(number))
            source, peer, target = self.nodes
            target_stamp = 10 if self.scenario == "key-change-older-target" else 30
            for node, channel, stamp in ((source, 15, 20), (target, 20, target_stamp)):
                for command in ("dataset init new", f"dataset channel {channel}",
                                f"dataset activetimestamp {stamp}", "dataset commit active"):
                    node.cmd(command)
            self.source_dataset, self.target_dataset = reads.active(source), reads.active(target)
            if self.scenario == "lost-api-result":
                target_fields = move.fields(self.target_dataset)
                target_fields[5] = move.fields(self.source_dataset)[5]
                target.cmd("dataset set active " + move.encode(target_fields))
                self.target_dataset = reads.active(target)
            peer.cmd("dataset set active " + self.source_dataset)
            for node in self.nodes:
                for command in ("routerselectionjitter 1", "ifconfig up", "thread start", "ba enable"):
                    node.cmd(command)
            move.wait_for(lambda: move.state(source) in ("leader", "router") and
                          move.state(peer) in ("leader", "router") and
                          move.state(target) == "leader" and
                          move.partition(source) == move.partition(peer), 120)
            if (move.partition(source) == move.partition(target) or
                    move.fields(reads.active(peer)) != move.fields(self.source_dataset) or
                    not all(move.pending_empty(node) for node in self.nodes)):
                raise reads.LabError("fixture_setup")
            self.births = [process_startticks(node.process.pid) for node in self.nodes]
            for node in self.nodes:
                node.read_only = True
            self.refresh()
        except BaseException:
            self.close()
            raise

    def _read(self, node, command):
        self.read_count += 1
        return node.cmd(command)

    def refresh(self):
        if len(self.nodes) != 3 or not all(node.read_only for node in self.nodes):
            raise reads.LabError("fixture_not_ready")
        self.refresh_stage = "process"
        for node, birth in zip(self.nodes, self.births):
            try:
                changed = node.process.poll() is not None or process_startticks(node.process.pid) != birth
            except (OSError, ValueError):
                changed = True
            if changed:
                raise reads.LabError("fixture_process_changed")
        source, peer, target = self.nodes
        self.refresh_stage = "ports"
        ports = [int(reads.value(self._read(node, "ba port"), r"^(\d+)$")) for node in self.nodes]
        if len(set(ports)) != 3 or not all(1 <= p <= 65535 for p in ports):
            raise reads.LabError("fixture_ports")
        self.refresh_stage = "datasets"
        datasets = [reads.value(self._read(node, "dataset active -x"), r"^([0-9a-fA-F]{80,})$").lower()
                    for node in self.nodes]
        self.refresh_stage = "states"
        states = [reads.value(self._read(node, "state"), r"^(leader|router|child|detached|disabled)$")
                  for node in self.nodes]
        self.refresh_stage = "partitions"
        partitions = [reads.value(self._read(node, "partitionid"), r"^(\d+)$") for node in self.nodes]
        self.refresh_stage = "pending"
        pending = [not move.pending_empty(node) for node in self.nodes]
        target_unchanged = move.fields(datasets[2]) == move.fields(self.target_dataset) and not pending[2]
        source_full_match = all(move.fields(item) == move.fields(self.target_dataset) for item in datasets[:2])
        same_partition = partitions[0] == partitions[1] == partitions[2]
        source_roles = all(role in ("leader", "router") for role in states[:2])
        # Before activation the source peer is the meaningful connectivity pair.
        destination = target if source_full_match and same_partition else source
        origin = peer
        self.refresh_stage = "connectivity"
        address = reads.value(self._read(destination, "ipaddr mleid"), r"^([0-9a-f:]+)$")
        connectivity = ping_once(origin, address)
        checked_at = int(time.time() * 1000)
        self.refresh_stage = "manifest"
        lines = ["TNT-FIXTURE/1", f"fixture_id {self.fixture_id}", "source_count 2"]
        for index in (0, 1):
            lines.append(f"source_node {self.node_ids[index]} {self.nodes[index].process.pid} {self.births[index]} {ports[index]}")
        lines.extend((f"target_node {self.node_ids[2]} {target.process.pid} {self.births[2]} {ports[2]}",
                      f"connectivity_checked_at_ms {checked_at}",
                      "connectivity_verified " + ("yes" if connectivity else "no"),
                      "discard_set_result " + ("yes" if self.scenario == "lost-api-result" else "no"),
                      "END"))
        atomic_manifest("\n".join(lines) + "\n", self.root / "fixture")
        self.refresh_count += 1
        self.last = {"source_full_match_target": source_full_match, "target_unchanged": target_unchanged,
                     "source_no_pending": not any(pending[:2]), "target_no_pending": not pending[2],
                     "same_partition": same_partition, "source_router_roles": source_roles,
                     "connectivity_verified": connectivity, "connectivity_checked_at_ms": checked_at,
                     "ports": ports, "states": states, "partitions": partitions,
                     "source_active_matches_original": [move.fields(item) == move.fields(self.source_dataset)
                                                        for item in datasets[:2]]}
        self.refresh_stage = None
        return self.last

    def response(self, action):
        if action == "refresh":
            return {"ok": True, "fixture_id": self.fixture_id, "metrics": self.refresh()}
        if action == "bootstrap":
            return {"ok": True, "fixture_id": self.fixture_id,
                    "source_dataset": self.source_dataset, "target_dataset": self.target_dataset,
                    "source_node_ids": self.node_ids[:2], "target_node_id": self.node_ids[2],
                    "delay_ms": 300000,
                    "scenario": self.scenario}
        if action == "discover":
            self.refresh()
            dataset_fields = (move.fields(self.source_dataset), move.fields(self.target_dataset))
            routers = []
            for i in range(3):
                fields = dataset_fields[0 if i < 2 else 1]
                routers.append({"service_name": f"Isolated {'source' if i < 2 else 'target'} {i + 1 if i < 2 else 1}",
                                "network_name": fields[3].decode("utf-8"),
                                "extended_pan_id": fields[2].hex(), "thread_version": "1.4",
                                "address": "::1", "port": self.last["ports"][i],
                                "fixture_node_id": self.node_ids[i]})
            return {"ok": True, "schema_version": 1, "discovery_status": "completed",
                    "fixture_id": self.fixture_id, "routers": routers}
        if action == "metrics":
            self.refresh()
            return {"ok": True, "fixture_id": self.fixture_id, "read_count": self.read_count,
                    "refresh_count": self.refresh_count, **self.last}
        return {"ok": False, "error": "unsupported_action"}

    def close(self):
        for node in reversed(self.nodes):
            node.close()
        self.nodes.clear()


def serve(fixture, runner):
    path = fixture.root / "control"
    if path.exists() or path.is_symlink():
        raise reads.LabError("unsafe_fixture_path")
    server = socket.socket(socket.AF_UNIX)
    child = None
    app_runs = 0
    last_event = {}
    selector = selectors.DefaultSelector()
    try:
        server.bind(str(path))
        os.chmod(path, 0o600)
        server.listen(4)
        server.setblocking(False)
        selector.register(server, selectors.EVENT_READ)
        next_refresh = time.monotonic() + 5
        for phase in ("dispatch", "recover"):
            env = os.environ.copy()
            env["TNT_FIXTURE_SOCKET"] = str(path)
            env["TNT_FIXTURE_MANIFEST"] = str(fixture.root / "fixture")
            env["TNT_FIXTURE_SCENARIO"] = fixture.scenario
            env["TNT_APP_PHASE"] = phase
            env["TNT_MOVE_LIFECYCLE_DIRECTORY"] = str(fixture.root / "lifecycle")
            env["TNT_MOVE_JOURNAL_DIRECTORY"] = str(fixture.root / "journal")
            env.setdefault("TNT_MOVE_WORKER", "/opt/app-build/thread-network-move-app")
            env.setdefault("TNT_MOVE_JOURNAL", "/opt/app-build/thread-move-journal")
            child = subprocess.Popen(runner, env=env, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     start_new_session=True)
            drains = [threading.Thread(target=drain_events,
                                       args=(stream, phase, last_event, fixture.app_outcomes), daemon=True)
                      for stream in (child.stdout, child.stderr)]
            for drain in drains:
                drain.start()
            app_runs += 1
            while child.poll() is None:
                for key, _ in selector.select(max(0, min(1, next_refresh - time.monotonic()))):
                    if key.fileobj is server:
                        connection, _ = server.accept()
                        with connection:
                            connection.settimeout(2)
                            handle_connection(connection, fixture)
                if time.monotonic() >= next_refresh:
                    fixture.refresh()
                    next_refresh = time.monotonic() + 5
            if child.returncode != 0:
                for drain in drains:
                    drain.join(timeout=2)
                return child.returncode, app_runs, phase, last_event.get(phase)
            for drain in drains:
                drain.join(timeout=2)
            child.stdout.close()
            child.stderr.close()
            child = None
            fixture.refresh()
        return 0, app_runs, "recover", last_event.get("recover")
    finally:
        selector.close()
        server.close()
        path.unlink(missing_ok=True)
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=3)
        if child is not None:
            child.stdout.close()
            child.stderr.close()


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", choices=("key-change-older-target", "lost-api-result"), required=True)
    parser.add_argument("--runner", nargs=argparse.REMAINDER, required=True)
    args = parser.parse_args(argv)
    if not args.runner:
        parser.error("--runner requires an executable and arguments")
    fixture = Fixture(args.scenario)
    stage = "setup"
    def deadline(_signal, _frame):
        raise TimeoutError("supervisor_deadline")
    prior_handler = signal.signal(signal.SIGALRM, deadline)
    signal.alarm(1000)
    try:
        fixture.setup()
        stage = "app"
        code, app_runs, phase, last_event = serve(fixture, args.runner)
        result = app_result(fixture, code, app_runs, phase, last_event)
        print(json.dumps(result, sort_keys=True))
        return 0 if code == 0 else 1
    except Exception as error:
        print(json.dumps(failure_report(fixture, stage, error), sort_keys=True))
        return 1
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, prior_handler)
        fixture.close()


if __name__ == "__main__":
    sys.exit(main())
