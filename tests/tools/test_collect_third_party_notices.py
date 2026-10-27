import argparse
import gzip
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.collect_third_party_notices import collect, git_head, source_revision


class NoticeCollectorTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        (self.app / ".dart_tool").mkdir()
        (self.app / "pubspec.lock").write_text(
            "packages:\n  sample:\n    dependency: direct main\n    version: 1.2.3\n",
            encoding="utf-8",
        )
        package = self.root / "packages/sample"
        package.mkdir(parents=True)
        (package / "LICENSE").write_text("Sample license\n", encoding="utf-8")
        (self.app / ".dart_tool/package_config.json").write_text(
            json.dumps({"packages": [{"name": "sample", "rootUri": package.as_uri()}]}),
            encoding="utf-8",
        )
        self.commissioner = self.root / "commissioner"
        for relative in (
            "LICENSE",
            "third_party/fmtlib/repo/LICENSE",
            "third_party/libevent/repo/LICENSE",
            "third_party/mbedtls/repo/LICENSE",
        ):
            path = self.commissioner / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"{relative}\n", encoding="utf-8")
        everest = self.commissioner/'third_party/mbedtls/repo/3rdparty/everest/example.c'
        everest.parent.mkdir(parents=True)
        everest.write_text('/* Copyright Example; SPDX-License-Identifier: Apache-2.0 */\nint excluded;')
        self.flutter = self.root / "flutter"
        for relative in ("packages/flutter/LICENSE", "bin/cache/dart-sdk/LICENSE"):
            path = self.flutter / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"{relative}\n", encoding="utf-8")
        self.flutter_notices = self.root / "NOTICES.Z"
        self.flutter_notices.write_bytes(gzip.compress(b"Generated Flutter notices\n"))
        self.output = self.root / "out"
        self.args = argparse.Namespace(
            output_dir=self.output,
            app_root=self.app,
            commissioner_root=self.commissioner,
            flutter_root=self.flutter,
            flutter_notices=self.flutter_notices,
        )
        self.revision_patcher = patch(
            "tools.collect_third_party_notices.source_revision",
            return_value=("a" * 40, ""),
        )
        self.revision_mock = self.revision_patcher.start()
        from tools.prepare_commissioner_source import MANIFEST
        self.provenance = json.loads(MANIFEST.read_text())
        self.provenance['prepared_tree_sha256'] = 'b' * 64
        (self.commissioner / 'tnt-source-provenance.json').write_text(json.dumps(self.provenance))
        self.verify_patcher = patch('tools.collect_third_party_notices.verify_prepared', return_value=self.provenance)
        self.verify_mock = self.verify_patcher.start()

    def tearDown(self):
        self.revision_patcher.stop()
        self.verify_patcher.stop()
        self.tmp.cleanup()

    def test_generated_source_records_pins_patch_and_tree(self):
        _, errors = collect(self.args)
        self.assertFalse(errors)
        self.assertEqual(json.loads((self.output/'commissioner/source-provenance.json').read_text()),self.provenance)
        manifest=(self.output/'MANIFEST.md').read_text()
        for pin in self.provenance['submodules'].values():
            if pin != self.provenance['submodules']['third_party/mbedtls/repo/framework']:
                self.assertIn(pin,manifest)
        self.assertTrue((self.output/'commissioner/source.patch').is_file())

    def test_rejects_tampered_generated_source_before_output(self):
        self.verify_mock.side_effect=ValueError('tree changed')
        with self.assertRaisesRegex(ValueError,'tree changed'):collect(self.args)
        self.assertFalse(self.output.exists())

    def test_detects_changed_tree_after_collection(self):
        self.verify_mock.side_effect=[self.provenance,ValueError('tree changed')]
        with self.assertRaisesRegex(ValueError,'tree changed'):collect(self.args)

    def test_missing_revision_marks_collection_incomplete(self):
        self.revision_mock.return_value = ("not established", "source revision unavailable")
        _, errors = collect(self.args)
        self.assertTrue(errors)
        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertIn("source revision unavailable", manifest)
        self.assertIn("Version/commit: not established", manifest)

    def test_dirty_revision_marks_collection_incomplete(self):
        self.revision_mock.return_value = (
            "a" * 40, "dirty source checkout; bytes may differ from commit")
        _, errors = collect(self.args)
        self.assertTrue(errors)
        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertIn("dirty source checkout; bytes may differ from commit", manifest)
        self.assertNotIn(str(self.root), manifest)

    def test_source_revision_rejects_missing_git_checkout(self):
        self.assertEqual(source_revision(self.commissioner),
                         ("not established", "source revision unavailable"))

    def test_source_revision_detects_tracked_changes(self):
        results = [
            subprocess.CompletedProcess([], 0, str(self.commissioner) + "\n", ""),
            subprocess.CompletedProcess([], 0, "b" * 40 + "\n", ""),
            subprocess.CompletedProcess([], 0, " M LICENSE\n", ""),
        ]
        with patch("tools.collect_third_party_notices.subprocess.run",
                   side_effect=results) as run:
            self.assertEqual(source_revision(self.commissioner),
                             ("b" * 40,
                              "dirty source checkout; bytes may differ from commit"))
        self.assertEqual(run.call_count, 3)

    def test_collects_license_sources_deterministically_and_sanitizes_paths(self):
        _, errors = collect(self.args)
        self.assertFalse(errors)
        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertIn("Dart package sample (direct main)", manifest)
        self.assertIn("Apache-2.0 OR GPL-2.0-or-later; selection unresolved", manifest)
        self.assertIn("Flutter packaged asset notice bundle", manifest)
        self.assertNotIn(str(self.root), manifest)
        self.assertEqual(
            (self.output / "flutter/NOTICES.txt").read_text(encoding="utf-8"),
            "Generated Flutter notices\n",
        )

    def test_refuses_to_overwrite_existing_output(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_text("preserve", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            collect(self.args)
        self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_reports_ambiguous_package_license_without_guessing(self):
        (self.root / "packages/sample/LICENSE.txt").write_text(
            "Second candidate\n", encoding="utf-8"
        )
        _, errors = collect(self.args)
        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertTrue(errors)
        self.assertIn("ambiguous license files: LICENSE, LICENSE.txt", manifest)
        self.assertFalse((self.output / "dart/sample.txt").exists())

    def test_collects_notice_for_package_inside_configured_flutter_sdk(self):
        sdk_package = self.flutter / "packages/flutter_test"
        sdk_package.mkdir(parents=True)
        sdk_license = self.flutter / "packages/flutter/LICENSE"
        sdk_license.write_text("Flutter SDK BSD notice\n", encoding="utf-8")
        config = json.loads((self.app / ".dart_tool/package_config.json").read_text())
        config["packages"].append({
            "name": "flutter_test",
            "rootUri": sdk_package.as_uri(),
        })
        (self.app / ".dart_tool/package_config.json").write_text(json.dumps(config))
        with (self.app / "pubspec.lock").open("a", encoding="utf-8") as lock:
            lock.write("  flutter_test:\n    dependency: direct dev\n    version: 0.0.0\n")

        _, errors = collect(self.args)

        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertFalse(errors)
        self.assertIn(
            "resolved Flutter SDK package flutter_test; SDK license: packages/flutter/LICENSE",
            manifest,
        )
        self.assertEqual(
            (self.output / "dart/flutter_test.txt").read_text(encoding="utf-8"),
            "Flutter SDK BSD notice\n",
        )

    def test_resolved_package_without_lock_version_is_a_gap(self):
        (self.app / "pubspec.lock").write_text("packages:\n", encoding="utf-8")
        _, errors = collect(self.args)
        self.assertTrue(errors)
        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertIn("package version not in lockfile", manifest)

    def test_missing_non_sdk_package_does_not_inherit_flutter_license(self):
        sdk_license = self.flutter / "packages/flutter/LICENSE"
        sdk_license.write_text("Flutter SDK BSD notice\n", encoding="utf-8")
        package = self.root / "packages/missing"
        package.mkdir(parents=True)
        config = json.loads((self.app / ".dart_tool/package_config.json").read_text())
        config["packages"].append({"name": "missing", "rootUri": package.as_uri()})
        (self.app / ".dart_tool/package_config.json").write_text(json.dumps(config))

        _, errors = collect(self.args)

        manifest = (self.output / "MANIFEST.md").read_text(encoding="utf-8")
        self.assertTrue(errors)
        self.assertIn("Dart package missing", manifest)
        self.assertIn("Status: missing license file", manifest)
        self.assertFalse((self.output / "dart/missing.txt").exists())

    def test_git_head_resolves_gitfile_loose_ref(self):
        repo = self.root / "checkout"
        gitdir = self.root / "metadata/worktrees/checkout"
        repo.mkdir()
        (gitdir / "refs/heads").mkdir(parents=True)
        (repo / ".git").write_text(f"gitdir: {gitdir}\n", encoding="utf-8")
        (gitdir / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
        (gitdir / "refs/heads/main").write_text("a" * 40 + "\n", encoding="utf-8")

        self.assertEqual(git_head(repo), "a" * 40)

    def test_git_head_resolves_gitfile_packed_ref(self):
        repo = self.root / "checkout"
        gitdir = self.root / "metadata/repository.git"
        repo.mkdir()
        gitdir.mkdir(parents=True)
        (repo / ".git").write_text(f"gitdir: {gitdir}\n", encoding="utf-8")
        (gitdir / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
        (gitdir / "packed-refs").write_text(
            "# pack-refs with: peeled fully-peeled\n" + "b" * 40 + " refs/heads/main\n",
            encoding="utf-8",
        )

        self.assertEqual(git_head(repo), "b" * 40)

    def test_git_head_resolves_worktree_common_dir_ref(self):
        repo = self.root / "checkout"
        common = self.root / "metadata/common.git"
        gitdir = common / "worktrees/checkout"
        repo.mkdir()
        (gitdir / "refs/heads").mkdir(parents=True)
        (repo / ".git").write_text(f"gitdir: {gitdir}\n", encoding="utf-8")
        (gitdir / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
        (gitdir / "commondir").write_text("../..\n", encoding="utf-8")
        (common / "refs/heads").mkdir(parents=True)
        (common / "refs/heads/main").write_text("c" * 40 + "\n", encoding="utf-8")

        self.assertEqual(git_head(repo), "c" * 40)


if __name__ == "__main__":
    unittest.main()
