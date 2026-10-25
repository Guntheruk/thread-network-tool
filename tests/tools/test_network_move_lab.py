import importlib.util
import json
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools/lab/commissioner"))
spec = importlib.util.spec_from_file_location("move_lab", root / "tools/lab/commissioner/move_driver.py")
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class NetworkMoveLabTests(unittest.TestCase):
    def test_public_report_drops_all_raw_context(self):
        report = lab.report("secret", {"secret": "raw-dataset"}, "secret", "secret", "secret", "secret")
        text = json.dumps(report)
        self.assertNotIn("secret", text)
        self.assertNotIn("raw-dataset", text)
        self.assertEqual(set(report["checks"]), set(lab.CHECKS))
        self.assertEqual(report["error_code"], "unexpected")

    def test_unknown_after_submit_is_explicitly_uncertain(self):
        report = lab.report("lost-api-result", {}, "submit", "deadline", "uncertain", "set_begin")
        self.assertEqual(report["dispatch_disposition"], "uncertain")
        self.assertEqual(report["last_worker_event"], "set_begin")
        self.assertEqual(report["status"], "failed")

    def test_oracle_blocks_all_dataset_writes_after_dispatch(self):
        node = object.__new__(lab.OracleNode)
        node.read_only = True
        for command in ("dataset set active secret", "dataset mgmtsetcommand pending -x secret",
                        "dataset commit active", "thread stop", "ba enable", "factoryreset"):
            with self.assertRaisesRegex(lab.reads.LabError, "oracle_write_blocked"):
                node.cmd(command)

    def test_full_dataset_comparison_is_order_independent_and_strict(self):
        first = "0e0800000000001400000410" + "aa"*16
        second = "0410" + "aa"*16 + "0e080000000000140000"
        self.assertEqual(lab.fields(first), lab.fields(second))
        self.assertNotEqual(lab.fields(first), lab.fields(first[:-2]+"bb"))
        for raw in (first+first, "0e08"+"00"*7, "00"):
            with self.assertRaisesRegex(lab.reads.LabError, "invalid_dataset"):
                lab.fields(raw)


if __name__ == "__main__":
    unittest.main()
