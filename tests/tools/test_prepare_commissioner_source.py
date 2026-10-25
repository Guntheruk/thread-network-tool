"""Offline source-preparation checks; optional integration uses a read-only pin."""
import hashlib
import io
import tarfile
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

    def test_rejects_fabricated_tree_with_self_declared_hash(self):
        self.output.mkdir()
        (self.output/'CMakeLists.txt').write_text('unrelated fabricated source')
        actual = dict(self.manifest)
        actual['prepared_tree_sha256'] = module.tree_hash(self.output)
        (self.output/'tnt-source-provenance.json').write_text(json.dumps(actual))
        with self.assertRaisesRegex(ValueError, 'provenance differs'):
            module.verify_prepared(self.output)

    def test_committed_identity_rejects_fabricated_tree_even_with_matching_provenance(self):
        self.output.mkdir()
        (self.output/'CMakeLists.txt').write_text('unrelated fabricated source')
        (self.output/'tnt-source-provenance.json').write_text(json.dumps(self.manifest))
        with self.assertRaisesRegex(ValueError, 'tree changed'):
            module.verify_prepared(self.output)

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

    def archive(self, entries):
        output=io.BytesIO()
        with tarfile.open(fileobj=output,mode='w') as archive:
            for item in entries:
                archive.addfile(item,io.BytesIO(b'x') if item.isfile() else None)
        return output.getvalue()

    def test_archive_file_modes_are_canonical_across_umasks(self):
        ordinary = tarfile.TarInfo('ordinary'); ordinary.size = 1; ordinary.mode = 0o600
        executable = tarfile.TarInfo('executable'); executable.size = 1; executable.mode = 0o700
        payload = self.archive([ordinary, executable])
        hashes = []
        for mask in (0o022, 0o077):
            destination = self.root/str(mask)
            previous = os.umask(mask)
            try:
                with patch.object(module, 'git', return_value=payload):
                    module.extract_archive(self.source, destination, module.PIN)
            finally:
                os.umask(previous)
            self.assertEqual((destination/'ordinary').stat().st_mode & 0o777, 0o644)
            self.assertEqual((destination/'executable').stat().st_mode & 0o777, 0o755)
            hashes.append(module.tree_hash(destination))
        self.assertEqual(hashes[0], hashes[1])

    def test_requires_safe_extraction_filter_capability(self):
        with patch.object(module.tarfile,'data_filter',None), self.assertRaisesRegex(ValueError,'data_filter'):
            module.extract_archive(self.source,self.output,module.PIN)
        self.assertFalse(self.output.exists())

    def test_rejects_escape_links_special_files_and_parent_paths(self):
        for name,kind,target in [('/absolute',tarfile.REGTYPE,''),('../parent',tarfile.REGTYPE,''),
                                 ('link',tarfile.SYMTYPE,'../outside'),('link',tarfile.SYMTYPE,'/outside'),
                                 ('link',tarfile.LNKTYPE,'safe'),('device',tarfile.CHRTYPE,'')]:
            item=tarfile.TarInfo(name);item.type=kind;item.linkname=target
            payload=self.archive([item])
            with patch.object(module,'git',return_value=payload), self.assertRaisesRegex(ValueError,'Unsafe'):
                module.extract_archive(self.source,self.output,module.PIN)
            self.assertFalse(self.output.exists())

    def test_earlier_symlink_cannot_redirect_later_member(self):
        link=tarfile.TarInfo('directory');link.type=tarfile.SYMTYPE;link.linkname='../outside'
        later=tarfile.TarInfo('directory/file');later.size=1
        payload=self.archive([link,later])
        with patch.object(module,'git',return_value=payload), self.assertRaisesRegex(ValueError,'Unsafe'):
            module.extract_archive(self.source,self.output,module.PIN)
        self.assertFalse((self.root/'outside/file').exists())
        self.assertFalse(self.output.exists())

    @unittest.skipUnless(os.environ.get('TNT_COMMISSIONER_TEST_SOURCE'),'provide clean pinned local source for integration')
    def test_actual_pin_reproducible_and_verify_tamper(self):
        source=Path(os.environ['TNT_COMMISSIONER_TEST_SOURCE'])
        before=module.source_repositories(source,self.manifest)
        first=module.prepare(source,self.output)
        other=self.root/'other'
        second=module.prepare(source,other)
        self.assertEqual(first,second)
        self.assertEqual(first['prepared_tree_sha256'], self.manifest['prepared_tree_sha256'])
        self.assertEqual(module.verify_prepared(self.output),first)
        from tools.resolve_commissioner_source import resolve
        self.assertEqual(resolve(source, self.output), self.output.resolve())
        self.assertEqual(resolve(self.output, self.root/'unused'), self.output.resolve())
        self.assertFalse((self.root/'unused').exists())
        # Preparation itself must also check the independent identity before
        # publishing any generated output, even if the manifest has a bad pin.
        bad_manifest = self.local_manifest()
        bad = json.loads(bad_manifest.read_text())
        bad['prepared_tree_sha256'] = '0' * 64
        bad_manifest.write_text(json.dumps(bad))
        with self.assertRaisesRegex(ValueError, 'committed identity'):
            module.prepare(source, self.root/'unpublished', bad_manifest)
        self.assertFalse((self.root/'unpublished').exists())
        # Frozen Python 3.11 images only verify; extraction filters are irrelevant.
        with patch.object(module.tarfile,'data_filter',None):
            self.assertEqual(module.verify_prepared(self.output),first)
        self.assertEqual(module.source_repositories(source,self.manifest),before)
        self.assertFalse((self.output/'.git').exists())
        self.assertEqual((source/'LICENSE').read_bytes(),(self.output/'LICENSE').read_bytes())
        self.assertIn('mLegacyWakeupChannel',(self.output/'include/commissioner/network_data.hpp').read_text())
        (self.output/'include/commissioner/network_data.hpp').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'tree changed'): module.verify_prepared(self.output)
        first['prepared_tree_sha256'] = module.tree_hash(self.output)
        (self.output/'tnt-source-provenance.json').write_text(json.dumps(first))
        with self.assertRaisesRegex(ValueError,'provenance differs'):
            module.verify_prepared(self.output)

if __name__ == '__main__': unittest.main()
