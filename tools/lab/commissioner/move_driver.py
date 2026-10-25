"""Actual guarded native move through three real Border Agents; isolated synthetic lab only."""
import json
import os
import re
import select
import signal
import subprocess
import sys
import time
import uuid
import driver as reads

APP_BASE = "242ba69a085d25b1bb9a4a04187c21553d32dd63"
WORKER = "/opt/app-build/thread-network-move-lab"
SCENARIOS = {"key-change-older-target", "same-key-newer-target", "lost-api-result"}
CHECKS = ("initial_two_source_routers", "native_guarded_submission", "source_only_petition",
          "one_pending_set_invocation", "pending_propagated", "target_unchanged",
          "source_converged", "same_partition", "source_router_roles", "connectivity",
          "native_authenticated_observation", "default_cli_read_only", "uncertainty_preserved",
          "loopback_guard", "bounded_stdin_guard", "read_only_oracle")


class OracleNode(reads.Node):
    read_only = False

    def cmd(self, command):
        allowed = command in {"state", "partitionid", "dataset active -x", "ba port", "ipaddr mleid"}
        allowed = allowed or bool(re.fullmatch(r"ping [0-9a-f:]+ 8 1", command))
        if self.read_only and not allowed:
            raise reads.LabError("oracle_write_blocked")
        return super().cmd(command)


def fields(dataset):
    raw = bytes.fromhex(dataset)
    result, offset = {}, 0
    while offset < len(raw):
        if offset + 2 > len(raw):
            raise reads.LabError("invalid_dataset")
        kind, size = raw[offset:offset+2]
        offset += 2
        if offset + size > len(raw) or kind in result:
            raise reads.LabError("invalid_dataset")
        result[kind] = raw[offset:offset+size]
        offset += size
    return result


def encode(dataset):
    return b"".join(bytes((kind, len(value))) + value for kind, value in dataset.items()).hex()


def state(node):
    return reads.value(node.cmd("state"), r"^(leader|router|child|detached|disabled)$")


def partition(node):
    return reads.value(node.cmd("partitionid"), r"^(\d+)$")


def pending_empty(node):
    # CLI has no pending record: use its precise pinned NotFound classification.
    os.write(node.master, b"dataset pending -ns\n")
    output = node.read(re.compile(r"(?:^|\n)(?:Done|Error \d+:[^\n]*)\n"), 12)
    if re.search(r"(?:^|\n)Error 23: NotFound\n", output):
        return True
    if "Pending Timestamp:" in output:
        return False
    raise reads.LabError("pending_read_unknown")


def wait_for(check, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return
        time.sleep(2)
    raise TimeoutError()


class Worker:
    def __init__(self, discard=False):
        self.process = subprocess.Popen([WORKER] + (["--lab-discard-set-result"] if discard else []),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.buffer = b""
        self.last_event = None

    def send(self, message):
        self.process.stdin.write(message.encode())
        self.process.stdin.flush()

    def trace(self):
        output = b""
        while len(output)<8192:
            ready, _, _ = select.select([self.process.stderr], [], [], 0)
            if not ready:
                break
            block = os.read(self.process.stderr.fileno(), 1024)
            if not block:
                break
            output += block
        for event in output.decode("ascii", "ignore").splitlines():
            if re.fullmatch(r"(?:active|pending|petition|set)_(?:begin|result(?::[0-9]{1,3})?)", event):
                self.last_event = event
        return self.last_event

    def read(self, timeout=90):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                if len(line) > 4096:
                    raise reads.LabError("output_limit")
                output = json.loads(line)
                if not isinstance(output, dict):
                    raise reads.LabError("worker_output")
                return output
            ready, _, _ = select.select([self.process.stdout], [], [], min(0.5, max(0, end-time.monotonic())))
            if ready:
                block = os.read(self.process.stdout.fileno(), 4096)
                if not block:
                    raise reads.LabError("worker_exit")
                self.buffer += block
                if len(self.buffer) > 8192:
                    raise reads.LabError("output_limit")
        raise TimeoutError()

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=3)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


def report(scenario, checks, stage, error=None, disposition=None, worker_event=None):
    result = {"schema_version": 1, "lab": "guarded-commissioner-network-move",
              "scenario": scenario if scenario in SCENARIOS else "unknown",
              "status": "failed" if error else "passed", "stage": stage if stage in {
                  "start", "form-networks", "preflight", "submit", "pending", "activation",
                  "partition", "connectivity", "native-observation", "complete"} else "unknown",
              "pins": {"app_base": APP_BASE, "openthread": reads.OT_PIN,
                       "commissioner": reads.COMMISSIONER_PIN},
              "checks": {key: checks.get(key) is True for key in CHECKS}}
    if error:
        result["error_code"] = error if error in {"deadline", "assertion", "simulator_command",
            "simulator_exit", "missing_value", "worker_exit", "worker_output", "output_limit",
            "invalid_dataset", "pending_read_unknown", "oracle_write_blocked"} else "unexpected"
    if disposition in {"proven_not_sent", "accepted", "rejected", "uncertain"}:
        result["dispatch_disposition"] = disposition
    if isinstance(worker_event, str) and re.fullmatch(r"(?:active|pending|petition|set)_(?:begin|result(?::[0-9]{1,3})?)", worker_event):
        result["last_worker_event"] = worker_event
    return result


def request(operation_id, source, target, source_ports, target_port, delay):
    return ("TNT-MOVE/1\noperation_id " + operation_id + "\nsource_dataset " + source +
        "\ntarget_dataset " + target + "\nsource_count 2\n" +
        "".join("source_endpoint ::1 " + str(port) + "\n" for port in source_ports) +
        "target_endpoint ::1 " + str(target_port) + "\ndelay_ms " + str(delay) +
        "\ncontrolled_empty yes\nrecovery manual-stop-and-observe\nEND\n")


def ping(node, address):
    for _ in range(5):
        response = node.cmd("ping " + address + " 8 1")
        if "from " not in response:
            try:
                response += node.read(re.compile(r"(?:\d+ bytes from|1 packets received)"), 12)
            except TimeoutError:
                pass
        if "from " in response or "1 packets received" in response:
            return True
        time.sleep(2)
    return False


def run(scenario):
    nodes, checks, worker = [], {}, None
    stage, disposition = "start", None
    try:
        if scenario not in SCENARIOS:
            raise reads.LabError("assertion")
        capability = subprocess.run([reads.APP, "capabilities"], text=True, capture_output=True, timeout=5)
        checks["default_cli_read_only"] = capability.returncode == 0 and json.loads(capability.stdout).get("network_writes") is False
        for number in (1, 2, 3):
            os.makedirs("/tmp/node" + str(number), exist_ok=True)
            nodes.append(OracleNode(number))
        source, peer, target = nodes
        stage = "form-networks"
        target_timestamp = 10 if scenario == "key-change-older-target" else 30
        delay = 300000 if scenario == "key-change-older-target" else 30000
        for node, channel, stamp in ((source, 15, 20), (target, 20, target_timestamp)):
            for command in ("dataset init new", "dataset channel " + str(channel),
                            "dataset activetimestamp " + str(stamp), "dataset commit active"):
                node.cmd(command)
        source_before, target_before = reads.active(source), reads.active(target)
        if scenario != "key-change-older-target":
            target_fields = fields(target_before)
            target_fields[5] = fields(source_before)[5]
            target.cmd("dataset set active " + encode(target_fields))
            target_before = reads.active(target)
        # All simulator writes end before the native worker starts.
        peer.cmd("dataset set active " + source_before)
        for node in nodes:
            for command in ("routerselectionjitter 1", "ifconfig up", "thread start", "ba enable"):
                node.cmd(command)
        wait_for(lambda: state(source) in ("leader", "router") and
                          state(peer) in ("leader", "router") and state(target) == "leader" and
                          partition(source) == partition(peer), 120)
        checks["initial_two_source_routers"] = (partition(source) == partition(peer) and
            partition(source) != partition(target) and fields(reads.active(peer)) == fields(source_before))
        if not checks["initial_two_source_routers"] or not all(pending_empty(node) for node in nodes):
            raise reads.LabError("assertion")
        source_ports = [int(reads.value(node.cmd("ba port"), r"^(\d+)$")) for node in (source, peer)]
        target_port = int(reads.value(target.cmd("ba port"), r"^(\d+)$"))
        for node in nodes:
            node.read_only = True
        checks["read_only_oracle"] = all(node.read_only for node in nodes)
        operation_id = uuid.uuid4().hex
        stage = "preflight"
        valid_request = request(operation_id, source_before, target_before, source_ports, target_port, delay)
        nonlocal_request = valid_request.replace("source_endpoint ::1 ", "source_endpoint 10.99.0.1 ", 1)
        guard = subprocess.run([WORKER], input=nonlocal_request, text=True, capture_output=True, timeout=5)
        rejected = json.loads(guard.stdout)
        checks["loopback_guard"] = guard.returncode != 0 and rejected.get("disposition") == "proven_not_sent"
        oversized = subprocess.run([WORKER], input="x"*17000+"\n", text=True, capture_output=True, timeout=5)
        checks["bounded_stdin_guard"] = (oversized.returncode != 0 and
            json.loads(oversized.stdout).get("disposition") == "proven_not_sent" and len(oversized.stdout)<1024)
        if not checks["loopback_guard"] or not checks["bounded_stdin_guard"]:
            raise reads.LabError("assertion")
        worker = Worker(scenario == "lost-api-result")
        worker.send(request(operation_id, source_before, target_before, source_ports, target_port, delay))
        review = worker.read()
        token = review.get("confirmation_token")
        if review.get("ready") is not True or not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{32}", token):
            raise reads.LabError("assertion")
        worker.send("confirm " + token + "\n")
        stage = "submit"
        disposition = "uncertain"
        submitted = worker.read()
        disposition = submitted.get("disposition")
        expected = "uncertain" if scenario == "lost-api-result" else "accepted"
        checks["native_guarded_submission"] = (disposition == expected and submitted.get("operation_id") == operation_id)
        checks["source_only_petition"] = submitted.get("petitions") == 1
        checks["one_pending_set_invocation"] = submitted.get("pending_set_invocations") == 1
        checks["uncertainty_preserved"] = disposition == expected
        if not all(checks.get(key) for key in ("native_guarded_submission", "source_only_petition", "one_pending_set_invocation", "uncertainty_preserved")):
            raise reads.LabError("assertion")
        stage = "pending"
        def observe_pending():
            worker.send("pending\n")
            return worker.read().get("verified") is True
        wait_for(observe_pending, 60)
        checks["pending_propagated"] = True
        checks["target_unchanged"] = fields(reads.active(target)) == fields(target_before) and pending_empty(target)
        if not checks["target_unchanged"]:
            raise reads.LabError("assertion")
        print(json.dumps({"lab": "guarded-commissioner-network-move", "status": "running", "stage": "pending_verified", "scenario": scenario}), flush=True)
        stage = "activation"
        wait_for(lambda: all(fields(reads.active(node)) == fields(target_before) and pending_empty(node)
                             for node in (source, peer)), delay/1000 + 90)
        checks["source_converged"] = True
        stage = "partition"
        wait_for(lambda: all(state(node) in ("leader", "router") for node in nodes) and
                 partition(source) == partition(peer) == partition(target), 150)
        checks["same_partition"] = checks["source_router_roles"] = True
        stage = "connectivity"
        address = reads.value(target.cmd("ipaddr mleid"), r"^([0-9a-f:]+)$")
        checks["connectivity"] = ping(peer, address)
        stage = "native-observation"
        def observe_converged():
            ports = [int(reads.value(node.cmd("ba port"), r"^(\d+)$")) for node in (source, peer)]
            current_target_port = int(reads.value(target.cmd("ba port"), r"^(\d+)$"))
            worker.send("observe 2\n" + "".join("source_endpoint ::1 " + str(port) + "\n" for port in ports) +
                        "target_endpoint ::1 " + str(current_target_port) + "\n")
            return worker.read().get("converged") is True
        wait_for(observe_converged, 60)
        checks["native_authenticated_observation"] = True
        checks["target_unchanged"] = fields(reads.active(target)) == fields(target_before) and pending_empty(target)
        if not all(checks.get(key) is True for key in CHECKS):
            raise reads.LabError("assertion")
        worker.send("quit\n")
        worker.process.wait(timeout=5)
        if worker.process.returncode != (2 if scenario == "lost-api-result" else 0):
            raise reads.LabError("assertion")
        return report(scenario, checks, "complete", disposition=disposition), 0
    except (TimeoutError, subprocess.TimeoutExpired):
        return report(scenario, checks, stage, "deadline", disposition, worker.trace() if worker else None), 1
    except Exception as exc:
        return report(scenario, checks, stage, str(exc), disposition, worker.trace() if worker else None), 1
    finally:
        if worker:
            worker.close()
        for node in reversed(nodes):
            node.close()


if __name__ == "__main__":
    def deadline(_sig, _frame):
        raise TimeoutError()
    signal.signal(signal.SIGALRM, deadline)
    signal.signal(signal.SIGTERM, deadline)
    signal.alarm(1000)
    result, code = run(os.environ.get("TNT_MOVE_SCENARIO", "key-change-older-target"))
    signal.alarm(0)
    print(json.dumps(result, sort_keys=True), flush=True)
    sys.exit(code)
