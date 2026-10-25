"""Offline source-preparation checks; optional integration uses a read-only pin."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_commissioner', ROOT/'tools/prepare_commissioner_source.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root/'input'
        self.source.mkdir()
        self.output = self.root/'output'
        self.manifest = json.loads(module.MANIFEST.read_text())

    def local_manifest(self):
        target = self.root/'manifest.json'
        target.write_text(json.dumps(self.manifest))
        (self.root/self.manifest['patch']).write_bytes((module.MANIFEST.parent/self.manifest['patch']).read_bytes())
        return target

    def test_patch_hash(self):
        self.assertEqual(hashlib.sha256((module.MANIFEST.parent/self.manifest['patch']).read_bytes()).hexdigest(),
                         self.manifest['patch_sha256'])

    def test_refuses_patch_tampering_before_source_or_output(self):
        manifest = self.local_manifest()
        (self.root/self.manifest['patch']).write_text('tampered')
        with self.assertRaisesRegex(ValueError,'hash mismatch'):
            module.prepare(self.source,self.output,manifest)
        self.assertFalse(self.output.exists())

    def test_refuses_existing_output(self):
        self.output.mkdir()
        marker=self.output/'keep'; marker.write_text('owner content')
        with self.assertRaisesRegex(ValueError,'already exists'):
            module.prepare(self.source,self.output)
        self.assertEqual(marker.read_text(),'owner content')

    def test_refuses_input_nested_output(self):
        with self.assertRaisesRegex(ValueError,'separate'):
            module.prepare(self.source,self.source/'generated')

    def fake_git(self, dirty=False, head=None, top=None):
        def run(repo,*args):
            if args == ('rev-parse','--show-toplevel'): return str(top or repo).encode()
            if args == ('rev-parse','HEAD'): return (head or module.PIN).encode()
            if args[0] == 'status': return b' M tracked.cpp' if dirty else b''
            raise AssertionError(args)
        return run

    def test_refuses_dirty_parent(self):
        with patch.object(module,'git',self.fake_git(dirty=True)), self.assertRaisesRegex(ValueError,'dirty'):
            module.verify(self.source,module.PIN)

    def test_refuses_wrong_parent_pin(self):
        with patch.object(module,'git',self.fake_git(head='0'*40)), self.assertRaisesRegex(ValueError,'revision'):
            module.verify(self.source,module.PIN)

    def test_refuses_uninitialized_submodule_parent_repo(self):
        with patch.object(module,'git',self.fake_git(top=self.root)), self.assertRaisesRegex(ValueError,'own repository'):
            module.verify(self.source,module.PIN)

    def test_refuses_manifest_submodule_mismatch(self):
        with patch.object(module,'verify'), patch.object(module,'gitlinks',return_value={}), self.assertRaisesRegex(ValueError,'submodule pin'):
            module.source_repositories(self.source,self.manifest)

    def test_refuses_dirty_recursive_submodule(self):
        def verify(repo,sha):
            if str(repo).endswith('/framework'): raise ValueError('Dependency source is dirty')
        root_links={p:self.manifest['submodules'][p] for p in module.REQUIRED}
        def links(repo):
            if repo == self.source: return root_links
            if str(repo).endswith('/mbedtls/repo'): return {'framework':self.manifest['submodules']['third_party/mbedtls/repo/framework']}
            return {}
        with patch.object(module,'verify',verify), patch.object(module,'gitlinks',links), self.assertRaisesRegex(ValueError,'dirty'):
            module.source_repositories(self.source,self.manifest)

    def test_tree_hash_detects_files_and_modes(self):
        (self.source/'file').write_text('original')
        original=module.tree_hash(self.source)
        (self.source/'file').write_text('changed')
        self.assertNotEqual(module.tree_hash(self.source),original)
        (self.source/'file').write_text('original')
        (self.source/'file').chmod(0o700)
        self.assertNotEqual(module.tree_hash(self.source),original)

    @unittest.skipUnless(os.environ.get('TNT_COMMISSIONER_TEST_SOURCE'),'provide clean pinned local source for integration')
    def test_actual_pin_reproducible_and_verify_tamper(self):
        source=Path(os.environ['TNT_COMMISSIONER_TEST_SOURCE'])
        before=module.source_repositories(source,self.manifest)
        first=module.prepare(source,self.output)
        other=self.root/'other'
        second=module.prepare(source,other)
        self.assertEqual(first,second)
        self.assertEqual(module.verify_prepared(self.output),first)
        self.assertEqual(module.source_repositories(source,self.manifest),before)
        self.assertFalse((self.output/'.git').exists())
        self.assertEqual((source/'LICENSE').read_bytes(),(self.output/'LICENSE').read_bytes())
        self.assertIn('mLegacyWakeupChannel',(self.output/'include/commissioner/network_data.hpp').read_text())
        (self.output/'include/commissioner/network_data.hpp').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'tree changed'): module.verify_prepared(self.output)

if __name__ == '__main__': unittest.main()
