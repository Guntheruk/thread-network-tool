import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[2] / "tools/lab/commissioner/driver.py"
spec = importlib.util.spec_from_file_location("commissioner_lab", path)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)

audit_path = Path(__file__).resolve().parents[2] / "tools/lab/commissioner/audit_source.py"
audit_spec = importlib.util.spec_from_file_location("commissioner_source_audit", audit_path)
audit = importlib.util.module_from_spec(audit_spec)
audit_spec.loader.exec_module(audit)


class CommissionerLabTests(unittest.TestCase):
    def test_error_report_drops_secrets_and_unknown_fields(self):
        report = lab.report({"source_authenticated": True, "secret": "pskc-secret"},
                            "source-probe", "raw-secret-dataset")
        encoded = json.dumps(report)
        self.assertNotIn("secret", encoded)
        self.assertEqual(report["error_code"], "unexpected")
        self.assertEqual(report["status"], "failed")
        self.assertEqual(set(report["checks"]), set(lab.CHECKS))
        self.assertEqual(lab.report({}, "secret", "secret")["stage"], "unknown")
        detail = lab.report({}, "form-networks", "simulator_command", "secret", "secret")
        self.assertEqual(detail["failed_command"], "unknown")
        self.assertNotIn("secret", json.dumps(detail))
        self.assertNotIn("cli_error_code", detail)
        safe = lab.report({}, "form-networks", "simulator_command", "ba_enable", 35)
        self.assertEqual(safe["cli_error_code"], 35)
        self.assertEqual(lab.command_label("dataset channel secret"), "dataset_channel")
        self.assertEqual(lab.command_label("secret secret"), "unknown")

    def test_probe_deadline_is_bounded_and_error_is_not_echoed(self):
        def runner(*args, **kwargs):
            self.assertEqual(kwargs["timeout"], 35)
            raise subprocess.TimeoutExpired(args[0], 35, output="secret")
        with self.assertRaises(TimeoutError):
            lab.probe("secret", 12345, runner)

    def test_malformed_or_oversized_probe_output_fails(self):
        for output, error in (("secret", "probe_output"), ("[]", "probe_output"),
                              ("x" * 8193, "output_limit")):
            def runner(*args, **kwargs):
                return subprocess.CompletedProcess(args[0], 1, output, "")
            with self.assertRaisesRegex(lab.LabError, error):
                lab.probe("00", 12345, runner)

    def test_timeout_outcome_is_typed(self):
        with patch.object(lab.subprocess, "run", side_effect=subprocess.TimeoutExpired("secret", 5)):
            report, code = lab.run()
        self.assertEqual(code, 1)
        self.assertEqual(report["error_code"], "deadline")
        self.assertNotIn("secret", json.dumps(report))

    def test_authentication_requires_matching_complete_read(self):
        good = {"probe_status": "completed", "authenticated": True,
                "identity_match": "match", "active_status": "read",
                "pending_status": "empty", "active_timestamp": "00000000000a0000"}
        self.assertTrue(lab.authenticated((0, good), "00000000000a0000"))
        for field, value in (("authenticated", False), ("identity_match", "mismatch"),
                             ("pending_status", "error"), ("active_timestamp", None)):
            self.assertFalse(lab.authenticated((0, dict(good, **{field: value})), "00000000000a0000"))
        self.assertFalse(lab.authenticated((1, good), "00000000000a0000"))

    def test_mismatched_timestamp_is_rejected(self):
        result = {"probe_status": "completed", "authenticated": True,
                  "identity_match": "match", "active_status": "read",
                  "pending_status": "empty", "active_timestamp": "ffffffffffffffff"}
        dataset = "0e08" + "00000000000a0000"
        self.assertFalse(lab.authenticated((0, result), lab.active_timestamp(dataset)))
        result["active_timestamp"] = "00000000000a0000"
        self.assertTrue(lab.authenticated((0, result), lab.active_timestamp(dataset)))

    def test_timestamp_baseline_rejects_missing_truncated_duplicate_tlv(self):
        for dataset in ("", "0e07" + "00" * 7, "0e08" + "00" * 7,
                        "0e08" + "00" * 8 + "0e08" + "00" * 8,
                        "0e08" + "00" * 8 + "00", "secret"):
            with self.assertRaisesRegex(lab.LabError, "invalid_dataset"):
                lab.active_timestamp(dataset)

    def test_wrong_pskc_changes_only_one_key_byte(self):
        dataset = "040f" + "11" * 15
        with self.assertRaisesRegex(lab.LabError, "missing_pskc"):
            lab.wrong_pskc(dataset)
        dataset = "0410" + "11" * 16 + "0003000014"
        wrong = lab.wrong_pskc(dataset)
        self.assertEqual(sum(a != b for a, b in zip(bytes.fromhex(dataset), bytes.fromhex(wrong))), 1)
        self.assertEqual(dataset[6:], wrong[6:])


class DependencySourceAuditTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tempdir)

    def git(self, repo, *args):
        result = subprocess.run(
            ["git", "-c", "protocol.file.allow=always", "-C", str(repo), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip()

    def commit(self, repo, message):
        self.git(repo, "add", ".")
        self.git(
            repo, "-c", "user.name=Lab Test", "-c", "user.email=lab@example.invalid",
            "commit", "-m", message,
        )
        return self.git(repo, "rev-parse", "HEAD")

    def fixture(self, name):
        leaf = self.tempdir / f"{name}-leaf"
        leaf.mkdir()
        self.git(leaf, "init")
        (leaf / "source.txt").write_text("first\n")
        old_leaf = self.commit(leaf, "leaf one")
        (leaf / "source.txt").write_text("second\n")
        leaf_pin = self.commit(leaf, "leaf two")

        middle = self.tempdir / f"{name}-middle"
        middle.mkdir()
        self.git(middle, "init")
        (middle / ".gitignore").write_text("build/\n")
        (middle / "source.txt").write_text("middle\n")
        self.git(middle, "submodule", "add", str(leaf), "framework")
        middle_pin = self.commit(middle, "middle")

        root = self.tempdir / name
        root.mkdir()
        self.git(root, "init")
        (root / "source.txt").write_text("root\n")
        self.git(root, "submodule", "add", str(middle), "third_party/mbedtls/repo")
        self.git(root, "submodule", "update", "--init", "--recursive")
        root_pin = self.commit(root, "root")
        pins = {
            "third_party/mbedtls/repo": middle_pin,
            "third_party/mbedtls/repo/framework": leaf_pin,
        }
        return root, root_pin, pins, old_leaf

    def fixtures(self):
        return [self.fixture("openthread"), self.fixture("ot-commissioner")]

    def test_valid_exact_recursive_trees_pass_for_both_dependencies(self):
        for root, root_pin, pins, _ in self.fixtures():
            audit.audit_dependency(root, root_pin, pins)

    def test_tracked_source_mutation_is_rejected_for_both_dependencies(self):
        for root, root_pin, pins, _ in self.fixtures():
            nested_source = root / "third_party/mbedtls/repo/source.txt"
            nested_source.write_text("mutated\n")
            with self.assertRaisesRegex(AssertionError, "dirty_dependency"):
                audit.audit_dependency(root, root_pin, pins)

    def test_wrong_recursive_submodule_revision_is_rejected_for_both_dependencies(self):
        for root, root_pin, pins, old_leaf in self.fixtures():
            nested = root / "third_party/mbedtls/repo/framework"
            self.git(nested, "checkout", "--detach", old_leaf)
            with self.assertRaisesRegex(AssertionError, "submodule_checkout_revision"):
                audit.audit_dependency(root, root_pin, pins)

    def test_uninitialized_recursive_submodule_is_rejected_for_both_dependencies(self):
        for root, root_pin, pins, _ in self.fixtures():
            middle = root / "third_party/mbedtls/repo"
            self.git(middle, "submodule", "deinit", "-f", "framework")
            with self.assertRaisesRegex(AssertionError, "uninitialized_submodule"):
                audit.audit_dependency(root, root_pin, pins)

    def test_ignored_untracked_build_cache_is_rejected_for_both_dependencies(self):
        for root, root_pin, pins, _ in self.fixtures():
            cache = root / "third_party/mbedtls/repo/build/cache.o"
            cache.parent.mkdir()
            cache.write_text("not pinned\n")
            with self.assertRaisesRegex(AssertionError, "dirty_dependency"):
                audit.audit_dependency(root, root_pin, pins)

    def test_dockerfile_audits_both_dependencies_before_their_builds(self):
        dockerfile = (audit_path.parent / "Dockerfile").read_text()
        ot_audit = dockerfile.index("dependency /opt/openthread 53e8322140")
        ot_build = dockerfile.index("./script/cmake-build simulation")
        commissioner_audit = dockerfile.index("dependency /opt/ot-commissioner 448f807e")
        commissioner_build = dockerfile.index("cmake -G Ninja")
        self.assertLess(ot_audit, ot_build)
        self.assertLess(commissioner_audit, ot_build)
        self.assertLess(commissioner_audit, commissioner_build)
        for pin in ("e185d7fd", "45799647", "40626af8", "4c908dde", "c765c831", "2a3e2c5e"):
            self.assertIn(pin, dockerfile)


if __name__ == "__main__":
    unittest.main()
