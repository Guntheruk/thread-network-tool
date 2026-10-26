"""Exercise package publication with synthetic toolchain/build boundaries.

The production shell script runs unchanged. CMake/Flutter/signing/provenance
preflight are fixture executables; the collector CLI contract validates that it
receives the actual newly built notice asset and chosen source/SDK/app paths.
Real collector contents/provenance are covered by test_collect_third_party_notices.
"""
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(platform.system() == 'Darwin', 'uses macOS ditto and exclusive rename')
class MacPackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tnt-package-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'candidate'
        (self.project / 'tools').mkdir(parents=True)
        shutil.copy2(ROOT / 'tools/build_macos_app.sh', self.project / 'tools')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.source = self.root / 'verified-generated'
        self.source.mkdir()
        for name in ['CMakeLists.txt', 'tnt-source-provenance.json']:
            (self.source / name).write_text('synthetic source\n')
        patches = self.project / 'patches/commissioner'
        patches.mkdir(parents=True)
        for name in ['manifest.json', 'legacy-wakeup-channel.patch']:
            (patches / name).write_text('synthetic provenance\n')
        self.native = self.root / 'native'
        self.native.mkdir()
        self.executable(self.native / 'thread-network',
                        '#!/bin/sh\nprintf \'{"authenticated_probe":true,"network_writes":false}\\n\'\n')
        self.output = self.root / 'published'
        self.sdk = self.root / 'selected-sdk'
        flutter = self.sdk / 'bin/flutter'
        self.executable(flutter, '''#!/usr/bin/env python3
import os
from pathlib import Path
root = Path.cwd()
app = root / 'build/macos/Build/Products/Release/Candidate.app'
(app / 'Contents/MacOS').mkdir(parents=True)
exe = app / 'Contents/MacOS/Candidate'
exe.write_text('fresh app')
exe.chmod(0o755)
(app / 'Contents/Info.plist').write_text('fixture')
notice = app / 'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/NOTICES.Z'
notice.parent.mkdir(parents=True)
notice.write_bytes(b'EXACT_FRESH_FLUTTER_NOTICE')
''')
        self.executable(self.bin / 'uname', '#!/bin/sh\necho Darwin\n')
        for name in ['xcodebuild', 'xcrun', 'cmake']:
            self.executable(self.bin / name, '#!/bin/sh\nexit 0\n')
        self.executable(self.bin / 'plutil', '#!/bin/sh\necho Candidate\n')
        self.executable(self.bin / 'lipo', '#!/bin/sh\necho arm64\n')
        (self.project / 'app').mkdir()
        self.executable(self.project / 'tools/resolve_commissioner_source.py',
                        'import os\nprint(os.environ["FIXTURE_SOURCE"])\n')
        (self.project / 'tools/prepare_commissioner_source.py').write_text('')
        self.executable(self.project / 'tools/bundle_macos_helper.sh',
                        '#!/bin/sh\nexit "${FIXTURE_BUNDLE_STATUS:-0}"\n')
        (self.project / 'tools/collect_third_party_notices.py').write_text('''import argparse
import json
import os
from pathlib import Path
p = argparse.ArgumentParser()
for name in ['output-dir', 'app-root', 'commissioner-root', 'flutter-root', 'flutter-notices']:
    p.add_argument('--' + name, type=Path, required=True)
a = p.parse_args()
assert a.app_root == Path(os.environ['FIXTURE_PROJECT']) / 'app'
assert a.commissioner_root == Path(os.environ['FIXTURE_SOURCE'])
assert a.flutter_root == Path(os.environ['FIXTURE_SDK'])
assert a.flutter_notices.read_bytes() == b'EXACT_FRESH_FLUTTER_NOTICE'
assert a.flutter_notices.is_relative_to(a.output_dir.parent)
assert not a.output_dir.exists()
assert not Path(os.environ['TNT_OUTPUT_DIR']).exists()
a.output_dir.mkdir()
status = int(os.environ.get('FIXTURE_COLLECT_STATUS', '0'))
(a.output_dir / 'MANIFEST.md').write_text('missing input: synthetic gap' if status else 'exact candidate manifest')
(a.output_dir / 'license.txt').write_text('verbatim synthetic license')
(a.output_dir / 'inputs.json').write_text(json.dumps({k: str(v) for k, v in vars(a).items()}))
if os.environ.get('FIXTURE_OUTPUT_COLLISION'):
    Path(os.environ['TNT_OUTPUT_DIR']).mkdir()
raise SystemExit(status)
''')
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer',
                        TNT_CMAKE_BIN=str(self.bin / 'cmake'), TNT_FLUTTER_BIN=str(flutter),
                        TNT_COMMISSIONER_SOURCE=str(self.source),
                        TNT_NATIVE_BUILD_DIR=str(self.native), TNT_OUTPUT_DIR=str(self.output),
                        FIXTURE_SOURCE=str(self.source), FIXTURE_PROJECT=str(self.project),
                        FIXTURE_SDK=str(self.sdk.resolve()))

    @staticmethod
    def executable(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def run_package(self, **env):
        return subprocess.run(['bash', str(self.project / 'tools/build_macos_app.sh')],
                              env={**self.env, **env}, capture_output=True, text=True)

    def test_success_retains_exact_notice_inputs_next_to_app(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.output / 'Candidate.app').is_dir())
        self.assertEqual((self.output / 'release-notices/MANIFEST.md').read_text(), 'exact candidate manifest')
        self.assertEqual((self.output / 'release-notices/license.txt').read_text(), 'verbatim synthetic license')
        for name in ['commissioner-source-provenance.json', 'commissioner-source-manifest.json', 'commissioner-source.patch']:
            self.assertTrue((self.output / name).is_file())
        self.assertFalse(list(self.root.glob('.published.stage.*')))

    def test_incomplete_collection_keeps_gap_evidence_without_publishing_app(self):
        result = self.run_package(FIXTURE_COLLECT_STATUS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        evidence = list(self.root.glob('.published.notices-failed.*/release-notices/MANIFEST.md'))
        self.assertEqual(len(evidence), 1, result.stderr)
        self.assertIn('missing input', evidence[0].read_text())
        self.assertFalse(list(self.root.glob('.published.stage.*')))

    def test_collector_exception_cannot_publish_partial_package(self):
        result = self.run_package(FIXTURE_COLLECT_STATUS='2')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.published.stage.*')))

    def test_prior_output_is_never_overwritten_or_extended(self):
        self.output.mkdir()
        (self.output / 'owner.txt').write_text('leave me')
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(p.name for p in self.output.iterdir()), ['owner.txt'])
        self.assertEqual((self.output / 'owner.txt').read_text(), 'leave me')

    def test_output_created_during_collection_is_not_replaced_or_nested(self):
        result = self.run_package(FIXTURE_OUTPUT_COLLISION='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.output.is_dir())
        self.assertEqual(list(self.output.iterdir()), [])
        self.assertFalse(list(self.root.glob('.published.stage.*')))

    def test_selected_flutter_symlink_resolves_to_actual_sdk(self):
        link = self.bin / 'flutter-selected'
        link.symlink_to(self.sdk / 'bin/flutter')
        result = self.run_package(TNT_FLUTTER_BIN=str(link))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.output / 'release-notices/MANIFEST.md').is_file())

    def test_signing_failure_cannot_publish_app_or_sidecars(self):
        result = self.run_package(FIXTURE_BUNDLE_STATUS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.published.stage.*')))


if __name__ == '__main__':
    unittest.main()
