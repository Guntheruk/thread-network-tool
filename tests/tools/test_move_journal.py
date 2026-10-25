"""Real POSIX files/processes: durability boundaries, restart and writer fences.

Run with TNT_JOURNAL_CLI and TNT_JOURNAL_FAULT pointing at compiled executables.
Fixtures contain only synthetic identifiers; no network operation is performed.
"""
import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


def record(op="a", revision=1, stage="dispatch_fenced", disposition="unknown", reason="none"):
    return (f"schema=1\noperation={op * 64}\nrevision={revision}\n"
            f"profile=openthread-posix-lab-v1\nstage={stage}\ndisposition={disposition}\n"
            f"source={'b' * 64}\ntarget={'c' * 64}\ntarget_router={'f' * 64}\n"
            f"routers={'d' * 64},{'e' * 64}\nfenced_at_ms=1000\nobserve_until_ms=401000\n"
            f"observation_seconds=10\nstable_since_ms=0\nstable_last_ms=0\nreason={reason}\n")


class JournalProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tnt-journal-test-")
        self.directory = Path(self.temp.name) / "private"
        self.cli = os.environ["TNT_JOURNAL_CLI"]
        self.fault = os.environ["TNT_JOURNAL_FAULT"]
        self.assertEqual(self.call("initialize").returncode, 0)

    def tearDown(self):
        self.temp.cleanup()

    def call(self, action, data="", revision=None):
        args = [self.cli, action, str(self.directory)]
        if revision is not None:
            args.append(str(revision))
        return subprocess.run(args, input=data, text=True, capture_output=True, timeout=10)

    def test_private_creation_and_restart(self):
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.call("read").stdout, "empty\n")
        self.assertEqual(self.call("begin", record()).returncode, 0)
        self.assertEqual(self.call("read").stdout, record())
        self.assertEqual((self.directory / "operation").stat().st_mode & 0o777, 0o600)

    def test_unresolved_fences_new_ids_and_duplicate_ids(self):
        self.assertEqual(self.call("begin", record()).returncode, 0)
        self.assertEqual(self.call("begin", record()).stdout, "operation_already_exists\n")
        self.assertEqual(self.call("begin", record(op="1")).stdout, "unresolved_operation\n")

    def test_cross_process_lock_contention(self):
        with open(self.directory / "writer.lock", "rb") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            self.assertEqual(self.call("begin", record()).stdout, "journal_busy\n")
        self.assertEqual(self.call("begin", record()).returncode, 0)

    def test_two_real_processes_cannot_both_begin(self):
        first = subprocess.Popen([self.cli, "begin", str(self.directory)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        second = subprocess.Popen([self.cli, "begin", str(self.directory)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        first.stdin.write(record())
        first.stdin.close()
        first.stdin = None
        second.stdin.write(record(op="1"))
        second.stdin.close()
        second.stdin = None
        first.communicate(timeout=10)
        second.communicate(timeout=10)
        self.assertEqual(sorted([first.returncode, second.returncode]), [0, 1])

    def test_status_cas_and_immutable_bindings(self):
        self.call("begin", record())
        accepted = record(revision=2, stage="observing", disposition="accepted", reason="worker_accepted")
        self.assertEqual(self.call("update", accepted, 1).returncode, 0)
        self.assertNotEqual(self.call("update", accepted, 1).returncode, 0)
        changed = record(revision=3, stage="needs_attention", disposition="accepted", reason="verification_failed").replace("c" * 64, "9" * 64)
        self.assertNotEqual(self.call("update", changed, 2).returncode, 0)
        self.assertEqual(self.call("read").stdout, accepted)

    def test_terminal_record_cannot_be_rewritten_and_old_id_cannot_replay(self):
        self.call("begin", record())
        complete = record(revision=2, stage="verified_complete", disposition="accepted", reason="verification_complete")
        complete = complete.replace("stable_since_ms=0", "stable_since_ms=391000").replace("stable_last_ms=0", "stable_last_ms=401000")
        self.assertEqual(self.call("update", complete, 1).returncode, 0)
        self.assertNotEqual(self.call("update", complete.replace("revision=2", "revision=3"), 2).returncode, 0)
        self.assertEqual(self.call("begin", record(op="1")).returncode, 0)
        done = record(op="1", revision=2, stage="proven_not_sent", disposition="proven_not_sent", reason="worker_not_sent")
        self.assertEqual(self.call("update", done, 1).returncode, 0)
        self.assertEqual(self.call("begin", record()).stdout, "operation_already_exists\n")

    def test_corruption_fails_closed(self):
        self.call("begin", record())
        (self.directory / "operation").write_text("broken\n")
        self.assertEqual(self.call("read").stdout, "journal_unavailable\n")
        self.assertEqual(self.call("begin", record(op="1")).stdout, "journal_unavailable\n")

    def test_symlinks_and_nonprivate_directory_fail_closed(self):
        self.directory.chmod(0o755)
        self.assertNotEqual(self.call("begin", record()).returncode, 0)
        self.directory.chmod(0o700)
        outside = Path(self.temp.name) / "outside"
        outside.write_text("unchanged")
        (self.directory / "operation").symlink_to(outside)
        self.assertNotEqual(self.call("begin", record()).returncode, 0)
        self.assertEqual(outside.read_text(), "unchanged")

    def test_injected_crash_at_each_durability_boundary(self):
        for point in ["after_file_sync", "after_rename", "after_directory_sync"]:
            with self.subTest(point=point):
                sub = self.directory / point
                subprocess.run([self.cli, "initialize", str(sub)], check=True, capture_output=True)
                child = subprocess.run([self.fault, "begin", str(sub), point], input=record(), text=True, capture_output=True)
                self.assertEqual(child.returncode, 73)
                current = subprocess.run([self.cli, "read", str(sub)], text=True, capture_output=True, check=True)
                self.assertEqual(current.stdout, "empty\n" if point == "after_file_sync" else record())
                duplicate = subprocess.run([self.cli, "begin", str(sub)], input=record(), text=True, capture_output=True)
                self.assertNotEqual(duplicate.returncode, 0)
                if point != "after_file_sync":
                    different = subprocess.run([self.cli, "begin", str(sub)], input=record(op="1"), text=True, capture_output=True)
                    self.assertEqual(different.stdout, "unresolved_operation\n")

    def test_crashed_status_update_keeps_global_fence(self):
        self.call("begin", record())
        update = record(revision=2, stage="observing", disposition="accepted", reason="worker_accepted")
        result = subprocess.run([self.fault, "update", str(self.directory), "after_file_sync"], input=update, text=True, capture_output=True)
        self.assertEqual(result.returncode, 73)
        self.assertEqual(self.call("read").stdout, record())
        self.assertEqual(self.call("begin", record(op="1")).stdout, "unresolved_operation\n")

    def test_secret_or_unknown_field_cannot_enter_record(self):
        for bad in [record() + "dataset=deadbeef\n", record().replace("reason=none", "reason=secret-value"), record().replace("source=" + "b" * 64, "source=household-label")]:
            self.assertNotEqual(self.call("begin", bad).returncode, 0)
        self.assertEqual(self.call("read").stdout, "empty\n")


if __name__ == "__main__":
    unittest.main()
