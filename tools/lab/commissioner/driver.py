"""Real application GET-only Commissioner/Border Agent lab; synthetic inputs only."""
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

OT_PIN = "53e8322140dde7b26827332100504507cec9cc4e"
COMMISSIONER_PIN = "448f807e3246c46e5b82e4cdc12a9b0fb2a646ae"
APP_PIN = "4cc1e80e7f1df1b810b252bdef5d729f41d2dde1"
CLI = "/opt/openthread/build/posix/src/posix/ot-cli"
RCP = "/opt/openthread/build/simulation/examples/apps/ncp/ot-rcp"
APP = "/opt/app-build/thread-network"
CHECKS = ("distinct_networks", "source_authenticated", "target_authenticated",
          "wrong_pskc_rejected", "datasets_unchanged", "read_only_capability")


class LabError(Exception):
    def __init__(self, code, command=None, cli_error=None):
        super().__init__(code)
        self.command = command
        self.cli_error = cli_error


def command_label(command):
    for prefix in ("dataset init", "dataset channel", "dataset activetimestamp", "dataset commit",
                   "dataset active", "ifconfig up", "thread start", "ba enable", "ba port", "state"):
        if command == prefix or command.startswith(prefix + " "):
            return prefix.replace(" ", "_")
    return "unknown"


class Node:
    def __init__(self, number):
        self.master, slave = pty.openpty()
        self.process = None
        try:
            self.process = subprocess.Popen(
                [CLI, "-I", "lo", "--data-path", "/tmp/node" + str(number),
                 "spinel+hdlc+forkpty://" + RCP + "?forkpty-arg=" + str(number)],
                stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            self.read(re.compile(r">\s*$"), 12)
        except BaseException:
            self.close()
            raise
        finally:
            os.close(slave)

    def read(self, pattern, timeout):
        deadline = time.monotonic() + timeout
        output = ""
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], min(0.5, max(0, deadline-time.monotonic())))
            if ready:
                try:
                    block = os.read(self.master, 4096)
                except OSError:
                    raise LabError("simulator_exit") from None
                if not block:
                    raise LabError("simulator_exit")
                output += block.decode("utf-8", "replace").replace("\r", "")
                if len(output) > 65536:
                    raise LabError("output_limit")
                if pattern.search(output):
                    return output
        raise TimeoutError()

    def cmd(self, command):
        os.write(self.master, (command + "\n").encode())
        output = self.read(re.compile(r"(?:^|\n)(?:Done|Error \d+:[^\n]*)\n"), 12)
        if "\nError " in output:
            match = re.search(r"(?:^|\n)Error (\d+):", output)
            raise LabError("simulator_command", command_label(command),
                           int(match.group(1)) if match else None)
        return output

    def close(self):
        if self.process is not None and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=2)
        os.close(self.master)


def value(output, pattern):
    match = re.search(pattern, output, re.MULTILINE)
    if not match:
        raise LabError("missing_value")
    return match.group(1)


def active(node):
    return value(node.cmd("dataset active -x"), r"^([0-9a-fA-F]{80,})$").lower()


def wrong_pskc(dataset):
    raw = bytearray.fromhex(dataset)
    offset = 0
    while offset + 2 <= len(raw):
        kind, length = raw[offset:offset+2]
        if offset + 2 + length > len(raw):
            break
        if kind == 4 and length == 16:
            raw[offset+2] ^= 0xff
            return raw.hex()
        offset += length + 2
    raise LabError("missing_pskc")


def probe(dataset, port, runner=subprocess.run):
    try:
        result = runner([APP, "probe", "::1", str(port)], input=dataset+"\n",
                        text=True, capture_output=True, timeout=35)
    except subprocess.TimeoutExpired:
        raise TimeoutError() from None
    if len(result.stdout) > 8192 or len(result.stderr) > 8192:
        raise LabError("output_limit")
    try:
        output = json.loads(result.stdout)
    except (ValueError, TypeError):
        raise LabError("probe_output") from None
    if not isinstance(output, dict):
        raise LabError("probe_output")
    return result.returncode, output


def active_timestamp(dataset):
    try:
        raw = bytes.fromhex(dataset)
    except ValueError:
        raise LabError("invalid_dataset") from None
    fields = {}
    offset = 0
    while offset < len(raw):
        if offset + 2 > len(raw):
            raise LabError("invalid_dataset")
        kind, length = raw[offset:offset+2]
        offset += 2
        if offset + length > len(raw) or kind in fields:
            raise LabError("invalid_dataset")
        fields[kind] = raw[offset:offset+length]
        offset += length
    if 14 not in fields or len(fields[14]) != 8:
        raise LabError("invalid_dataset")
    return fields[14].hex()


def authenticated(result, expected_timestamp):
    code, output = result
    return (code == 0 and output.get("probe_status") == "completed" and
            output.get("authenticated") is True and output.get("identity_match") == "match" and
            output.get("active_status") == "read" and output.get("pending_status") == "empty" and
            bool(re.fullmatch(r"[0-9a-f]{16}", expected_timestamp)) and
            output.get("active_timestamp") == expected_timestamp)


def report(checks, stage, error=None, command=None, cli_error=None):
    output = {"schema_version": 1, "lab": "commissioner-border-agent-read",
              "status": "failed" if error else "passed", "stage": stage if stage in {"start", "form-networks", "source-probe", "target-probe", "wrong-pskc", "unchanged", "complete"} else "unknown",
              "pins": {"openthread": OT_PIN, "commissioner": COMMISSIONER_PIN, "app": APP_PIN},
              "checks": {key: checks.get(key) is True for key in CHECKS}}
    if error:
        output["error_code"] = error if error in {"deadline", "simulator_exit", "output_limit",
            "simulator_command", "missing_value", "missing_pskc", "probe_output", "invalid_dataset", "assertion"} else "unexpected"
    if error == "simulator_command":
        output["failed_command"] = command if command in {
            "dataset_init", "dataset_channel", "dataset_activetimestamp", "dataset_commit",
            "dataset_active", "ifconfig_up", "thread_start", "ba_enable", "ba_port", "state"} else "unknown"
        if type(cli_error) is int and 0 <= cli_error <= 65535:
            output["cli_error_code"] = cli_error
    return output


def run():
    nodes, checks, stage = [], {}, "start"
    try:
        capabilities = subprocess.run([APP, "capabilities"], capture_output=True, text=True, timeout=5)
        cap = json.loads(capabilities.stdout)
        checks["read_only_capability"] = (capabilities.returncode == 0 and
            cap.get("authenticated_probe") is True and cap.get("network_writes") is False)
        if not checks["read_only_capability"]:
            raise LabError("assertion")
        stage = "form-networks"
        for number, channel, stamp in ((1, 15, 10), (3, 20, 20)):
            os.makedirs("/tmp/node" + str(number), exist_ok=True)
            node = Node(number)
            nodes.append(node)
            for command in ("dataset init new", "dataset channel " + str(channel),
                            "dataset activetimestamp " + str(stamp), "dataset commit active",
                            "ifconfig up", "thread start", "ba enable"):
                node.cmd(command)
        deadline = time.monotonic() + 60
        while any("\nleader\n" not in node.cmd("state") for node in nodes):
            if time.monotonic() > deadline:
                raise TimeoutError()
            time.sleep(1)
        datasets = [active(node) for node in nodes]
        checks["distinct_networks"] = datasets[0] != datasets[1]
        ports = [int(value(node.cmd("ba port"), r"^(\d+)$")) for node in nodes]
        if not checks["distinct_networks"] or len(set(ports)) != 2 or not all(ports):
            raise LabError("assertion")
        for role, dataset, port in zip(("source", "target"), datasets, ports):
            stage = role + "-probe"
            checks[role + "_authenticated"] = authenticated(probe(dataset, port), active_timestamp(dataset))
            if not checks[role + "_authenticated"]:
                raise LabError("assertion")
        stage = "wrong-pskc"
        code, output = probe(wrong_pskc(datasets[0]), ports[0])
        checks["wrong_pskc_rejected"] = (code != 0 and output.get("authenticated") is False and
            output.get("probe_status") in ("error", "timeout"))
        stage = "unchanged"
        checks["datasets_unchanged"] = all(active(node) == dataset for node, dataset in zip(nodes, datasets))
        if not all(checks.get(key) is True for key in CHECKS):
            raise LabError("assertion")
        return report(checks, "complete"), 0
    except (TimeoutError, subprocess.TimeoutExpired):
        return report(checks, stage, "deadline"), 1
    except Exception as exc:
        return report(checks, stage, str(exc), getattr(exc, "command", None),
                      getattr(exc, "cli_error", None)), 1
    finally:
        for node in reversed(nodes):
            node.close()


def main():
    def deadline(_sig, _frame):
        raise TimeoutError()
    signal.signal(signal.SIGALRM, deadline)
    signal.signal(signal.SIGTERM, deadline)
    signal.alarm(180)
    result, code = run()
    signal.alarm(0)
    print(json.dumps(result, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
