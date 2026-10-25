import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from tools import resolve_commissioner_source as resolver

class ResolveSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.source=Path(self.tmp.name).resolve()/'source';self.source.mkdir()
        self.output=Path(self.tmp.name).resolve()/'output'
    def test_generated_source_is_verified_and_used_without_copy(self):
        (self.source/'tnt-source-provenance.json').write_text('{}')
        with patch.object(resolver.source_tools,'verify_prepared') as verify, patch.object(resolver.source_tools,'prepare') as prepare:
            self.assertEqual(resolver.resolve(self.source,self.output),self.source)
            verify.assert_called_once_with(self.source);prepare.assert_not_called()
    def test_cache_prepares_only_a_separate_output(self):
        with patch.object(resolver.source_tools,'source_repositories'), patch.object(resolver.source_tools,'prepare') as prepare:
            self.assertEqual(resolver.resolve(self.source,self.output),self.output)
            prepare.assert_called_once_with(self.source,self.output)
    def test_cache_reuse_checks_both_original_and_generation(self):
        self.output.mkdir()
        with patch.object(resolver.source_tools,'source_repositories') as pins, patch.object(resolver.source_tools,'verify_prepared') as verify:
            self.assertEqual(resolver.resolve(self.source,self.output),self.output)
            pins.assert_called_once();verify.assert_called_once_with(self.output)
    def test_dirty_cache_blocks_existing_generation(self):
        self.output.mkdir()
        with patch.object(resolver.source_tools,'source_repositories',side_effect=ValueError('dirty')), self.assertRaisesRegex(ValueError,'dirty'):
            resolver.resolve(self.source,self.output)
