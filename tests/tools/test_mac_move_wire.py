#!/usr/bin/env python3
"""Opt-in loopback-only Commissioner wire test; synthetic public credentials."""
import hashlib
import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

WORKER: Path
PEER: Path
CHILDREN = []


def dataset(target):
    fields = {
        0: bytes((0, 0, 15)), 1: bytes((0x12, 0x34)), 2: bytes((2 if target else 1,)) * 8,
        3: b"Lab", 4: bytes((0xbb if target else 0xaa,)) * 16,
        5: bytes((0x22 if target else 0x11,)) * 16, 7: bytes((0xfd, 0, 0, 0, 0, 0, 0, 1)),
        12: bytes((0, 0, 0)), 14: bytes((0, 0, 0, 0, 0, 10 if target else 20, 0, 0)),
        53: bytes((0, 4, 0, 0x1f, 0xff, 0xe0)),
    }
    return b"".join(bytes((key, len(value))) + value for key, value in sorted(fields.items())).hex()


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def start_peer(role, mode="accept", port=None):
    args = [str(PEER), role, mode]
    if port is not None:
        args.append(str(port))
    child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    CHILDREN.append(child)
    ready = json.loads(child.stdout.readline())
    assert ready["event"] == "ready", ready
    return child, ready["port"]


def stop_peer(child):
    child.send_signal(signal.SIGTERM)
    result = json.loads(child.stdout.readline())
    child.wait(timeout=5)
    assert result["event"] == "counts", result
    return result


def invoke(body, timeout=45):
    result = subprocess.run([str(WORKER)], input=body, text=True, capture_output=True, timeout=timeout)
    return result.returncode, json.loads(result.stdout)


def request(mode, operation, journal, routers, target, fenced=0, expected="-"):
    rows = [
        "TNT-MAC-MOVE/1", f"mode {mode}", f"operation_id {operation}",
        f"review_revision {'b'*64}", "source_generation 1", "target_generation 2",
        f"session_id {'c'*64}", f"discovery_revision {'d'*64}",
        f"connectivity_revision {'e'*64}", f"source_dataset {dataset(False)}",
        f"target_dataset {dataset(True)}", f"source_count {len(routers)}",
    ]
    for identity, port in routers:
        rows.append(f"source_router {identity} ::1 {port}")
    rows.extend((f"target_router {target[0]} ::1 {target[1]}", "delay_ms 300000",
                 f"inventory_attestation {'f'*64}", "controlled_empty yes", "manual_recovery yes",
                 f"lifecycle_directory {journal}", f"fenced_at_ms {fenced}",
                 f"expected_binding {expected}", "END", ""))
    return "\n".join(rows)


def fence(journal, inspected, operation, fenced, source_override=None,
          stage="dispatch_fenced", disposition="unknown", reason="none", revision=1):
    bindings = sorted(inspected["source_bindings"])
    fields = [
        "schema=1", f"operation={operation}", f"revision={revision}",
        "profile=eero-source-network-alpha-v1", f"stage={stage}", f"disposition={disposition}",
        f"source={source_override or inspected['source_commitment']}",
        f"target={inspected['target_commitment']}",
        f"target_router={inspected['target_binding']}", f"routers={','.join(bindings)}",
        f"fenced_at_ms={fenced}", f"observe_until_ms={fenced+330000}",
        "observation_seconds=30", "stable_since_ms=0", "stable_last_ms=0", f"reason={reason}", "",
    ]
    fd = os.open(journal / "operation", os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    try:
        os.write(fd, "\n".join(fields).encode())
        os.fsync(fd)
    finally:
        os.close(fd)


def main():
    global WORKER, PEER
    if len(sys.argv) != 3:
        raise SystemExit("usage: test_mac_move_wire.py WORKER FIXTURE")
    WORKER, PEER = map(Path, sys.argv[1:])
    with tempfile.TemporaryDirectory(prefix="tnt-mac-wire-") as temporary:
        journal = Path(temporary)
        source_a, port_a = start_peer("source")
        source_b, port_b = start_peer("source")
        target_child, port_target = start_peer("target")
        routers = [(sha(f"::1:{port_a}"), port_a), (sha(f"::1:{port_b}"), port_b)]
        target = (sha(f"::1:{port_target}"), port_target)
        operation = "a" * 64
        code, inspected = invoke(request("inspect", operation, journal, routers, target))
        inspect_counts = [stop_peer(child) for child in (source_a, source_b, target_child)]
        assert code == 0 and inspected.get("ready") and inspected.get("profile_id") == "eero-source-network-alpha-v1", (inspected, inspect_counts)
        assert [row["pending_set"] for row in inspect_counts] == [0, 0, 0]
        source_a, _ = start_peer("source", port=port_a)
        source_b, _ = start_peer("source", port=port_b)
        target_child, _ = start_peer("target", port=port_target)
        fenced = int(time.time() * 1000)
        fence(journal, inspected, operation, fenced, source_override="0"*64)
        code, blocked = invoke(request("dispatch", operation, journal, routers, target, fenced, inspected["binding_commitment"]))
        assert code == 1 and blocked["reason"] == "journal_mismatch", blocked
        assert [stop_peer(child)["pending_set"] for child in (source_a, source_b, target_child)] == [0, 0, 0]
        source_a, _ = start_peer("source", port=port_a)
        source_b, _ = start_peer("source", port=port_b)
        target_child, _ = start_peer("target", port=port_target)
        fence(journal, inspected, operation, fenced)
        code, dispatched = invoke(request("dispatch", operation, journal, routers, target, fenced, inspected["binding_commitment"]))
        counts = [stop_peer(child) for child in (source_a, source_b, target_child)]
        assert code == 0 and dispatched["pending_set_invocations"] == 1, dispatched
        assert sum(row["pending_set"] for row in counts) == 1, (dispatched, counts)
        assert counts[2]["petition"] == 0 and counts[2]["pending_set"] == 0, counts
        assert dispatched["disposition"] == "accepted", dispatched
        source_a, _ = start_peer("target", port=port_a)
        source_b, _ = start_peer("target", port=port_b)
        target_child, _ = start_peer("target", port=port_target)
        fence(journal, inspected, operation, fenced, stage="observing",
              disposition="accepted", reason="worker_accepted", revision=2)
        code, observed = invoke(request("observe", operation, journal, routers, target, fenced))
        observation_counts = [stop_peer(child) for child in (source_a, source_b, target_child)]
        assert code == 0 and observed["converged"] and observed["target_unchanged"], observed
        assert all(row["full_match"] and row["authenticated"] and row["pending_empty"]
                   and not row["connectivity_verified"] for row in observed["sources"]), observed
        assert all(row["pending_set"] == 0 and row["petition"] == 0 for row in observation_counts)
        print("PASS: authenticated full snapshots, journal tamper zero SET, one source Petition/SET, target GET-only, exact settings observation")

    for mode in ("reject", "drop"):
        with tempfile.TemporaryDirectory(prefix=f"tnt-mac-{mode}-") as temporary:
            journal = Path(temporary)
            source, source_port = start_peer("source", mode)
            target_child, target_port = start_peer("target")
            routers = [(sha(f"::1:{source_port}"), source_port)]
            target = (sha(f"::1:{target_port}"), target_port)
            operation = ("b" if mode == "reject" else "c") * 64
            code, inspected = invoke(request("inspect", operation, journal, routers, target))
            assert code == 0 and inspected.get("ready"), inspected
            stop_peer(source)
            stop_peer(target_child)
            source, _ = start_peer("source", mode, source_port)
            target_child, _ = start_peer("target", port=target_port)
            fenced = int(time.time() * 1000)
            fence(journal, inspected, operation, fenced)
            body = request("dispatch", operation, journal, routers, target, fenced,
                           inspected["binding_commitment"])
            if mode == "drop":
                worker = subprocess.Popen([str(WORKER)], stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                CHILDREN.append(worker)
                worker.stdin.write(body)
                worker.stdin.close()
                ready, _, _ = select.select([source.stdout], [], [], 20)
                assert ready, "synthetic SET was not observed"
                assert json.loads(source.stdout.readline())["event"] == "pending_set"
                worker.send_signal(signal.SIGTERM)
                dispatched = json.loads(worker.stdout.readline())
                code = worker.wait(timeout=5)
            else:
                code, dispatched = invoke(body, timeout=60)
            source_counts, target_counts = stop_peer(source), stop_peer(target_child)
            expected = "rejected" if mode == "reject" else "uncertain"
            assert code == (124 if mode == "drop" else 0) and dispatched["disposition"] == expected, dispatched
            if mode != "drop":
                assert dispatched["petitions"] == 1 and dispatched["pending_set_invocations"] == 1
            assert source_counts["pending_set"] == 1 and source_counts["petition"] == 1, source_counts
            assert target_counts["pending_set"] == 0 and target_counts["petition"] == 0, target_counts
            source, _ = start_peer("source", mode, source_port)
            target_child, _ = start_peer("target", port=target_port)
            code, replayed = invoke(body)
            replay_counts = [stop_peer(child) for child in (source, target_child)]
            assert code != 0 and replayed["reason"] == "operation_already_started", replayed
            assert all(row["pending_set"] == 0 and row["petition"] == 0 for row in replay_counts)
            if mode == "reject":
                source, _ = start_peer("source", port=source_port)
                target_child, _ = start_peer("target", port=target_port)
                fence(journal, inspected, operation, fenced, stage="observing",
                      disposition="rejected", reason="worker_rejected", revision=2)
                code, observed = invoke(request("observe", operation, journal, routers, target, fenced), timeout=60)
                stop_peer(source)
                stop_peer(target_child)
                assert code == 0 and observed["original_source_unchanged_rejected"], observed
                assert observed["sources"][0]["full_match"] and observed["target"]["full_match"], observed
                assert not observed["converged"] and not observed["sources"][0]["connectivity_verified"], observed
            print(f"PASS: {mode} response, one logical source SET, no target SET, no replay")


if __name__ == "__main__":
    try:
        main()
    finally:
        for child in CHILDREN:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
