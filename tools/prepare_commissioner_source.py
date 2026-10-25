#!/usr/bin/env python3
"""Prepare a fresh generated legacy-compatible source tree; never mutate inputs.

Archives only tracked clean pinned sources, including the required recursive
submodules. No clone, fetch, checkout, credential, or network operation occurs.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'patches/commissioner/manifest.json'
PIN = '448f807e3246c46e5b82e4cdc12a9b0fb2a646ae'
REQUIRED = ('third_party/fmtlib/repo', 'third_party/libevent/repo', 'third_party/mbedtls/repo')


def git(repo: Path, *args: str) -> bytes:
    return subprocess.run(['git', '-C', str(repo), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def gitlinks(repo: Path) -> dict[str, str]:
    result = {}
    for entry in git(repo, 'ls-tree', '-rz', 'HEAD').split(b'\0'):
        if entry:
            meta, path = entry.split(b'\t', 1)
            mode, _, sha = meta.decode().split()
            if mode == '160000':
                result[path.decode()] = sha
    return result


def verify(repo: Path, expected: str) -> None:
    # rev-parse also succeeds in a parent repo: insist this is its own root.
    if Path(git(repo, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != repo.resolve():
        raise ValueError('Dependency is not its own repository')
    if git(repo, 'rev-parse', 'HEAD').decode().strip() != expected:
        raise ValueError('Dependency revision does not match manifest')
    if git(repo, 'status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Dependency source is dirty')


def source_repositories(source: Path, manifest: dict) -> list[tuple[str, str]]:
    verify(source, PIN)
    pins = manifest['submodules']
    found = []
    def visit(parent: Path, prefix: str, paths: tuple[str, ...] | None = None) -> None:
        links = gitlinks(parent)
        for relative in (paths if paths is not None else sorted(links)):
            full = f'{prefix}/{relative}' if prefix else relative
            expected = links.get(relative)
            if not expected or pins.get(full) != expected:
                raise ValueError('Recursive submodule pin differs from manifest')
            repo = source / full
            verify(repo, expected)
            found.append((full, expected))
            visit(repo, full)
    visit(source, '', REQUIRED)
    if dict(found) != pins:
        raise ValueError('Manifest contains missing or unused recursive pins')
    return [('', PIN), *found]


def extract_archive(repo: Path, destination: Path, revision: str) -> None:
    payload = git(repo, 'archive', '--format=tar', revision)
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        for item in archive.getmembers():
            name = PurePosixPath(item.name)
            if name.is_absolute() or '..' in name.parts or item.isdev() or item.islnk():
                raise ValueError('Unsafe source archive member')
            if item.issym():
                target = PurePosixPath(item.linkname)
                if target.is_absolute() or '..' in target.parts:
                    raise ValueError('Unsafe source archive symlink')
        archive.extractall(destination, filter='data')


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if relative == 'tnt-source-provenance.json':
            continue
        digest.update(relative.encode() + b'\0')
        if path.is_symlink():
            digest.update(b'L' + os.readlink(path).encode())
        elif path.is_file():
            digest.update(b'F' + str(path.stat().st_mode & 0o777).encode() + b'\0' + path.read_bytes())
        else:
            digest.update(b'D')
    return digest.hexdigest()


def prepare(source: Path, destination: Path, manifest_path: Path = MANIFEST) -> dict:
    source = source.resolve()
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError('Output already exists; use a fresh generated directory')
    destination = destination.resolve()
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError('Input and output source directories must be separate')
    manifest = json.loads(manifest_path.read_text())
    if manifest['schema_version'] != 1 or manifest['revision'] != PIN:
        raise ValueError('Unexpected source manifest')
    patch = manifest_path.parent / manifest['patch']
    if patch.parent.resolve() != manifest_path.parent.resolve():
        raise ValueError('Patch must be adjacent to manifest')
    patch_bytes = patch.read_bytes()
    if hashlib.sha256(patch_bytes).hexdigest() != manifest['patch_sha256']:
        raise ValueError('Compatibility patch hash mismatch')
    repositories = source_repositories(source, manifest)
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.tnt-commissioner-', dir=destination.parent))
    try:
        for relative, revision in repositories:
            extract_archive(source / relative, stage / relative, revision)
        # Check and apply the same in-memory bytes, never change the verified input.
        apply_env = os.environ.copy()
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
            apply_env.pop(key, None)
        apply_env['GIT_CEILING_DIRECTORIES'] = str(stage.parent)
        for args in (['git', 'apply', '--check'], ['git', 'apply']):
            subprocess.run(args, cwd=stage, env=apply_env, input=patch_bytes, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if source_repositories(source, manifest) != repositories:
            raise ValueError('Input changed during preparation')
        provenance = dict(manifest)
        provenance['prepared_tree_sha256'] = tree_hash(stage)
        (stage / 'tnt-source-provenance.json').write_text(json.dumps(provenance, sort_keys=True, indent=2) + '\n')
        # Reserve the destination without replacing any pre-existing path.
        destination.mkdir()
        try:
            for item in stage.iterdir():
                shutil.move(str(item), str(destination / item.name))
        except BaseException:
            shutil.rmtree(destination)
            raise
        return provenance
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def verify_prepared(destination: Path, manifest_path: Path = MANIFEST) -> dict:
    expected = json.loads(manifest_path.read_text())
    patch = manifest_path.parent / expected['patch']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != expected['patch_sha256']:
        raise ValueError('Compatibility patch hash mismatch')
    actual = json.loads((destination / 'tnt-source-provenance.json').read_text())
    if {k: v for k, v in actual.items() if k != 'prepared_tree_sha256'} != expected:
        raise ValueError('Prepared source provenance differs from manifest')
    if actual['prepared_tree_sha256'] != tree_hash(destination):
        raise ValueError('Prepared source tree changed')
    return actual


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if not args.verify_only and args.source is None:
        parser.error('--source is required when preparing')
    try:
        result = verify_prepared(args.output) if args.verify_only else prepare(args.source, args.output)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Do not echo command output, source content, or arbitrary filenames.
        parser.exit(1, f'Commissioner source preparation refused ({type(error).__name__}).\n')
    print(json.dumps({'profile': result['profile'], 'revision': result['revision'],
                      'patch_sha256': result['patch_sha256'],
                      'prepared_tree_sha256': result['prepared_tree_sha256']}, sort_keys=True))

if __name__ == '__main__':
    main()
