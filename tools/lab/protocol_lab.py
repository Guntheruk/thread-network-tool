"""Isolated OpenThread protocol proof for a source-network Pending Dataset move.

Only synthetic simulator nodes are addressed. Output is an allowlisted JSON report.
"""

import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

CLI = "/opt/openthread/build/simulation/examples/apps/cli/ot-cli-ftd"
COMMAND_TIMEOUT = 12
SETTLE_TIMEOUT = 480


def tlvs(hex_text):
    raw = bytes.fromhex(hex_text)
    result = {}
    pos = 0
    while pos < len(raw):
        if pos + 2 > len(raw):
            raise ValueError("truncated TLV header")
        kind, size = raw[pos], raw[pos + 1]
        pos += 2
        if pos + size > len(raw) or kind in result:
            raise ValueError("truncated or duplicate TLV")
        result[kind] = raw[pos:pos + size]
        pos += size
    return result


def pending_hex(target_hex, source_hex, delay_ms=30000):
    target, source = tlvs(target_hex), tlvs(source_hex)
    if 14 not in target or 14 not in source or 5 not in target or 5 not in source:
        raise ValueError("incomplete synthetic dataset")
    if len(target[14]) != 8 or len(source[14]) != 8:
        raise ValueError("invalid active timestamp")
    if target[5] == source[5] or target.get(2) == source.get(2):
        raise ValueError("synthetic networks not distinct")
    pending_seconds = max(int.from_bytes(target[14], "big") >> 16,
                          int.from_bytes(source[14], "big") >> 16) + 1
    pending = b"\x33\x08" + (pending_seconds << 16).to_bytes(8, "big")
    delay = b"\x34\x04" + delay_ms.to_bytes(4, "big")
    return target_hex + pending.hex() + delay.hex()


class Node:
    def __init__(self, number):
        master, slave = pty.openpty()
        self.master = master
        self.process = subprocess.Popen([CLI, str(number)], stdin=slave,
                                        stdout=slave, stderr=slave,
                                        start_new_session=True, close_fds=True)
        os.close(slave)
        self._read_until(re.compile(r">\s*$"), 10)

    def _read_until(self, pattern, timeout):
        end = time.monotonic() + timeout
        chunks = ""
        while time.monotonic() < end:
            ready, _, _ = select.select([self.master], [], [], min(1, end - time.monotonic()))
            if not ready:
                continue
            block = os.read(self.master, 65536).decode("utf-8", "replace")
            chunks += block.replace("\r", "")
            if pattern.search(chunks):
                return chunks
            if len(chunks) > 65536:
                raise RuntimeError("simulator output exceeded limit")
        raise TimeoutError("simulator response deadline")

    def cmd(self, command, allow_error=False):
        os.write(self.master, (command + "\n").encode())
        output = self._read_until(re.compile(r"(?:^|\n)(?:Done|Error \d+:[^\n]*)\n"),
                                  COMMAND_TIMEOUT)
        if "\nError " in output and not allow_error:
            raise RuntimeError("simulator command rejected: " + command.split()[0])
        return output

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=3)
        os.close(self.master)


def value(output, pattern):
    match = re.search(pattern, output, re.MULTILINE)
    if not match:
        raise RuntimeError("expected simulator value absent")
    return match.group(1)


def active_hex(node):
    return value(node.cmd("dataset active -x"), r"^([0-9a-fA-F]{80,})$").lower()


def pending_present(node):
    result = node.cmd("dataset pending -ns", allow_error=True)
    if "Pending Timestamp:" in result:
        return True
    if re.search(r"(?:^|\n)Error 23: NotFound\n", result):
        return False
    raise RuntimeError("pending_read_unknown")


def state(node):
    return value(node.cmd("state"), r"^(leader|router|child|detached|disabled)$")


def partition(node):
    return value(node.cmd("partitionid"), r"^(\d+)$")


def wait_for(check, timeout, label):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return
        time.sleep(2)
    raise TimeoutError(label + " deadline")


def ping_reachable(node, address, attempts=5):
    for attempt in range(attempts):
        response = node.cmd("ping " + address + " 8 1")
        if "from " not in response:
            try:
                response += node._read_until(
                    re.compile(r"(?:\d+ bytes from|1 packets received)"), 12)
            except TimeoutError:
                pass
        if "from " in response or "1 packets received" in response:
            return True
        if attempt + 1 < attempts:
            time.sleep(3)
    return False


def report(status, checks, stage, error=None):
    allowed = {"source_distinct_before", "source_propagated", "target_unchanged",
               "source_converged", "source_router_roles", "same_partition",
               "connectivity"}
    result = {"schema_version": 1, "lab": "openthread-network-pending-set",
              "status": status, "stage": stage, "pending_set_calls": checks.get("pending_set_calls", 0),
              "checks": {key: bool(checks.get(key, False)) for key in sorted(allowed)}}
    if error:
        result["error_code"] = error
    return result


def run():
    nodes = []
    checks = {}
    stage = "start"
    try:
        for number in (1, 2, 3):
            nodes.append(Node(number))
        target, source, source_peer = nodes
        for node, channel, timestamp in ((target, 15, 10), (source, 20, 20)):
            node.cmd("dataset init new")
            node.cmd("dataset channel " + str(channel))
            node.cmd("dataset activetimestamp " + str(timestamp))
            node.cmd("dataset commit active")
            node.cmd("ifconfig up")
            node.cmd("thread start")
        stage = "form-networks"
        wait_for(lambda: state(target) == "leader" and state(source) == "leader",
                 60, stage)
        target_before, source_before = active_hex(target), active_hex(source)
        source_peer.cmd("dataset set active " + source_before)
        source_peer.cmd("ifconfig up")
        source_peer.cmd("thread start")
        wait_for(lambda: state(source_peer) in ("child", "router"), 60,
                 "source-peer-attach")
        checks["source_distinct_before"] = (
            tlvs(target_before)[2] != tlvs(source_before)[2] and
            active_hex(source_peer) == source_before and
            partition(target) != partition(source))
        if not checks["source_distinct_before"]:
            raise RuntimeError("preflight_mismatch")
        if pending_present(target) or pending_present(source) or pending_present(source_peer):
            raise RuntimeError("pending_preexists")
        stage = "submit-pending"
        pending = pending_hex(target_before, source_before)
        checks["pending_set_calls"] = 1
        source.cmd("dataset mgmtsetcommand pending -x " + pending)
        stage = "observe-pending"
        wait_for(lambda: pending_present(source) and pending_present(source_peer),
                 45, stage)
        checks["source_propagated"] = True
        checks["target_unchanged"] = active_hex(target) == target_before and not pending_present(target)
        if not checks["target_unchanged"]:
            raise RuntimeError("target_changed")
        stage = "observe-activation"
        wait_for(lambda: (active_hex(source) == target_before and
                          active_hex(source_peer) == target_before and
                          not pending_present(source) and
                          not pending_present(source_peer)),
                 SETTLE_TIMEOUT, stage)
        checks["source_converged"] = True
        checks["target_unchanged"] = active_hex(target) == target_before and not pending_present(target)
        if not checks["target_unchanged"]:
            raise RuntimeError("target_changed")
        wait_for(lambda: state(source) in ("router", "leader") and
                          state(source_peer) in ("router", "leader"),
                 120, "source-router-roles")
        checks["source_router_roles"] = True
        wait_for(lambda: partition(target) == partition(source) == partition(source_peer),
                 90, "merge-partition")
        checks["same_partition"] = True
        stage = "connectivity"
        target_eid = value(target.cmd("ipaddr mleid"), r"^([0-9a-f:]+)$")
        checks["connectivity"] = ping_reachable(source_peer, target_eid)
        if not checks["connectivity"]:
            raise RuntimeError("ping_failed")
        checks["target_unchanged"] = active_hex(target) == target_before and not pending_present(target)
        if not checks["target_unchanged"]:
            raise RuntimeError("target_changed")
        return report("passed", checks, "complete"), 0
    except TimeoutError:
        return report("failed", checks, stage, "deadline"), 1
    except Exception as exc:
        code = str(exc)
        if code not in {"preflight_mismatch", "pending_preexists", "pending_read_unknown",
                        "target_changed", "ping_failed"}:
            code = "unexpected"
        return report("failed", checks, stage, code), 1
    finally:
        for node in reversed(nodes):
            node.close()


if __name__ == "__main__":
    def _deadline(_signum, _frame):
        raise TimeoutError("overall deadline")

    signal.signal(signal.SIGALRM, _deadline)
    signal.signal(signal.SIGTERM, _deadline)
    signal.alarm(600)
    result, exit_code = run()
    signal.alarm(0)
    print(json.dumps(result, sort_keys=True))
    sys.exit(exit_code)
