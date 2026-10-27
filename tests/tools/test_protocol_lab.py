import importlib.util
from pathlib import Path
import signal
import unittest

MODULE = Path(__file__).resolve().parents[2] / "tools/lab/protocol_lab.py"
spec = importlib.util.spec_from_file_location("protocol_lab", MODULE)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


def dataset(key, xpan, stamp):
    return ("0e08" + (stamp << 16).to_bytes(8, "big").hex() +
            "0510" + key * 16 + "0208" + xpan * 8)


class ProtocolLabTests(unittest.TestCase):
    def test_pending_wire_payload_contains_target_and_one_timer(self):
        target = dataset("aa", "11", 10)
        source = dataset("bb", "22", 20)
        result = lab.tlvs(lab.pending_hex(target, source))
        self.assertEqual(result[5], bytes.fromhex("aa" * 16))
        self.assertEqual(int.from_bytes(result[51], "big") >> 16, 21)
        self.assertEqual(int.from_bytes(result[52], "big"), 30000)

    def test_duplicate_tlv_rejected(self):
        with self.assertRaises(ValueError):
            lab.tlvs("0208111111111111111102082222222222222222")

    def test_report_allowlist_excludes_secrets_and_endpoints(self):
        result = lab.report("failed", {"source_propagated": True,
            "network_key": "a" * 32, "endpoint": "192.0.2.1", "pending_set_calls": 1},
            "observe-pending", "deadline")
        self.assertEqual(result["pending_set_calls"], 1)
        self.assertNotIn("network_key", str(result))
        self.assertNotIn("endpoint", str(result))

    def test_pending_empty_requires_specific_not_found(self):
        class FakeNode:
            def __init__(self, reply):
                self.reply = reply
            def cmd(self, _command, allow_error=False):
                return self.reply

        self.assertFalse(lab.pending_present(FakeNode("Error 23: NotFound\n")))
        self.assertTrue(lab.pending_present(FakeNode("Pending Timestamp: 2\nDone\n")))
        for reply in ("Error 5: Busy\n", "Error 23: Other\n", "Done\n"):
            with self.subTest(reply=reply), self.assertRaises(RuntimeError):
                lab.pending_present(FakeNode(reply))

    def test_failure_report_remains_bounded(self):
        result = lab.report("failed", {"pending_set_calls": 1,
            "source_propagated": False, "raw_dataset": "aa" * 1000},
            "observe-pending", "pending_read_unknown")
        self.assertEqual(set(result), {"schema_version", "lab", "status", "stage",
                                      "pending_set_calls", "checks", "error_code"})
        self.assertLess(len(str(result)), 500)

    def test_ping_retry_uses_later_success(self):
        class FakeNode:
            calls = 0
            def cmd(self, _command):
                self.calls += 1
                return "Done\n" if self.calls == 1 else "8 bytes from peer\nDone\n"
            def _read_until(self, _pattern, _timeout):
                raise TimeoutError("first ping lost")

        node = FakeNode()
        original_sleep = lab.time.sleep
        lab.time.sleep = lambda _seconds: None
        try:
            self.assertTrue(lab.ping_reachable(node, "fd00::1", attempts=2))
            self.assertEqual(node.calls, 2)
        finally:
            lab.time.sleep = original_sleep

    def test_overall_deadline_during_ping_does_not_retry(self):
        class FakeNode:
            calls = 0
            def cmd(self, _command):
                self.calls += 1
                return "Done\n"
            def _read_until(self, _pattern, _timeout):
                signal.raise_signal(signal.SIGALRM)

        node = FakeNode()
        prior_handler = signal.getsignal(signal.SIGALRM)
        signal.signal(signal.SIGALRM, lab.overall_deadline_signal)
        try:
            with self.assertRaises(lab.OverallDeadlineExceeded):
                lab.ping_reachable(node, "fd00::1", attempts=5)
            self.assertEqual(node.calls, 1)
        finally:
            signal.signal(signal.SIGALRM, prior_handler)

    def test_overall_deadline_has_typed_redacted_report(self):
        original_node = lab.Node
        def expired(_number):
            raise lab.OverallDeadlineExceeded()
        lab.Node = expired
        try:
            result, exit_code = lab.run()
        finally:
            lab.Node = original_node
        self.assertEqual(exit_code, 1)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["error_code"], "overall_deadline")
        self.assertEqual(result["pending_set_calls"], 0)
        self.assertNotIn("dataset", str(result))


if __name__ == "__main__":
    unittest.main()
