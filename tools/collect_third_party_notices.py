#!/usr/bin/env python3
"""Collect local third-party license texts without network access.

The collector is intentionally conservative: it copies only a uniquely named
license file for a resolved Dart package and known license files from the
verified generated Commissioner tree. Flutter's generated notice bundle is copied
from the already-built macOS release app when available. Missing and ambiguous
inputs are listed in the manifest instead of guessed.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

# Importable both as tools.module and as a directly invoked script.
try:
    from .prepare_commissioner_source import verify_prepared, MANIFEST as COMMISSIONER_MANIFEST
except ImportError:
    from prepare_commissioner_source import verify_prepared, MANIFEST as COMMISSIONER_MANIFEST
from urllib.parse import unquote, urlparse


LICENSE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING", "COPYING.txt")
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMMISSIONER = ROOT / "vendor/ot-commissioner"
DEFAULT_FLUTTER = ROOT / ".tooling/flutter"
DEFAULT_FLUTTER_NOTICES = (
    ROOT / "build/macos-package/Thread Network Tool.app/Contents/Frameworks/"
    "App.framework/Versions/A/Resources/flutter_assets/NOTICES.Z"
)


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_lock_roles(lock_path: Path) -> dict[str, str]:
    """Read only package dependency role from pub's simple lockfile shape."""
    roles: dict[str, str] = {}
    current = None
    for line in lock_path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^  ([^\s][^:]*):\s*$", line)
        if match:
            current = match.group(1)
        elif current and line.startswith("    dependency:"):
            roles[current] = line.split(":", 1)[1].strip().strip('"')
    return roles


def resolve_root_uri(uri: str, config_dir: Path) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    if parsed.scheme:
        raise ValueError(f"unsupported package root URI scheme: {parsed.scheme}")
    return (config_dir / unquote(uri)).resolve()


def unique_license(root: Path) -> tuple[Path | None, str]:
    if not root.is_dir():
        return None, "missing package root"
    found = [root / n for n in LICENSE_NAMES if (root / n).is_file()]
    if not found:
        return None, "missing license file"
    if len(found) > 1:
        return None, "ambiguous license files: " + ", ".join(p.name for p in found)
    return found[0], "found"


def git_head(path: Path) -> str:
    dot_git = path / ".git"
    if dot_git.is_file():
        text = dot_git.read_text(encoding="utf-8", errors="replace").strip()
        if not text.startswith("gitdir:"):
            return "unknown"
        gitdir = (path / text.partition(":")[2].strip()).resolve()
    elif dot_git.is_dir():
        gitdir = dot_git.resolve()
    else:
        return "unknown"
    try:
        head = gitdir / "HEAD"
        value = head.read_text(encoding="utf-8").strip()
        if value.startswith("ref: "):
            ref = value[5:]
            common_dir_file = gitdir / "commondir"
            common_dir = (gitdir / common_dir_file.read_text(encoding="utf-8").strip()).resolve() \
                if common_dir_file.is_file() else gitdir
            for refs_dir in (gitdir, common_dir):
                refpath = refs_dir / ref
                if refpath.is_file():
                    return refpath.read_text(encoding="utf-8").strip()
            for packed in (gitdir / "packed-refs", common_dir / "packed-refs"):
                if packed.is_file():
                    for line in packed.read_text(encoding="utf-8").splitlines():
                        if line and not line.startswith(("#", "^")) and line.endswith(" " + ref):
                            return line.split()[0]
            return "unresolved"
        return value
    except OSError:
        return "unknown"


def source_revision(path: Path) -> tuple[str, str]:
    """Return a clean exact commit or an explicit provenance gap."""
    try:
        def run(*args: str) -> subprocess.CompletedProcess[str]:
            return subprocess.run(["git", "-C", str(path), *args],
                                  capture_output=True, text=True, check=False)

        root = run("rev-parse", "--show-toplevel")
        head = run("rev-parse", "--verify", "HEAD^{commit}")
        if (root.returncode or head.returncode or
                Path(root.stdout.strip()).resolve() != path.resolve() or
                not re.fullmatch(r"[0-9a-fA-F]{40,64}", head.stdout.strip())):
            return "not established", "source revision unavailable"
        revision = head.stdout.strip().lower()
        dirty = run("status", "--porcelain=v1", "--untracked-files=no")
        if dirty.returncode:
            return revision, "source cleanliness unavailable"
        if dirty.stdout.strip():
            return revision, "dirty source checkout; bytes may differ from commit"
        return revision, ""
    except OSError:
        return "not established", "source revision unavailable"


def flutter_sdk_package_license(root: Path, flutter_root: Path) -> Path | None:
    """Use Flutter's own BSD notice only for package roots in its source tree."""
    package_root = (flutter_root / "packages").resolve()
    resolved_root = root.resolve()
    try:
        resolved_root.relative_to(package_root)
    except ValueError:
        return None
    candidate = flutter_root / "packages/flutter/LICENSE"
    return candidate if candidate.is_file() else None


def commissioner_sources(source: Path, provenance: dict | None = None) -> list[tuple[str, Path, str, str, str]]:
    # Only components present in the configured link command are collected.
    components = [
        ("OpenThread Commissioner", source, "LICENSE",
         "BSD-3-Clause (upstream source license)"),
        ("fmt", source / "third_party/fmtlib/repo", "LICENSE", "MIT"),
        ("libevent", source / "third_party/libevent/repo", "LICENSE", "BSD-3-Clause"),
        ("Mbed TLS (includes p256-m; Everest separately recorded)",
         source / "third_party/mbedtls/repo", "LICENSE",
         "Apache-2.0 OR GPL-2.0-or-later; selection unresolved"),
    ]
    provenance = provenance if provenance is not None else verify_prepared(source)
    rows = []
    for name, root, license_path, license_name in components:
        relative = root.relative_to(source).as_posix()
        revision = provenance['revision'] if relative == '.' else provenance['submodules'][relative]
        rows.append((name, root / license_path, revision, '', license_name))
    return rows


def configured_commissioner_root() -> Path:
    """Use the local CMake cache path when present, without emitting it."""
    cache = ROOT / "build/native-probe/CMakeCache.txt"
    if cache.is_file():
        for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("TNT_COMMISSIONER_SOURCE:"):
                candidate = Path(line.split("=", 1)[1])
                if candidate.is_dir():
                    return candidate
    return DEFAULT_COMMISSIONER


def copy_text(src: Path, dst: Path) -> str:
    data = src.read_bytes()
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)
    return sha256(data)


def collect(args: argparse.Namespace) -> tuple[list[str], bool]:
    commissioner_provenance = verify_prepared(args.commissioner_root)
    output = args.output_dir
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing output directory: {output}")
    if not output.parent.is_dir():
        raise FileNotFoundError(f"output parent does not exist: {output.parent}")
    output.mkdir()

    rows: list[dict[str, str]] = []
    errors = False
    for name, src, revision, provenance, license_name in commissioner_sources(args.commissioner_root, commissioner_provenance):
        target = output / "commissioner" / (safe_name(name) + ".txt")
        if src.is_file():
            digest = copy_text(src, target)
            status = "collected" if not provenance else f"collected; {provenance}"
            errors |= bool(provenance)
        else:
            digest = ""
            status = "missing license text"
            errors = True
        rows.append({"component": name, "version_or_commit": revision,
                     "license": license_name,
                     "source": "verified generated Commissioner source: " + src.relative_to(args.commissioner_root).as_posix(),
                     "status": status, "sha256": digest,
                     "output": target.relative_to(output).as_posix() if digest else ""})

    # Everest has Apache-only notices, distinct from the Mbed TLS dual terms.
    # Preserve every distinct leading source/header copyright block, without code.
    everest = args.commissioner_root / 'third_party/mbedtls/repo/3rdparty/everest'
    blocks = set()
    for path in sorted(everest.rglob('*')):
        if path.is_file() and path.suffix in ('.c', '.h'):
            match = re.match(r'\s*(/\*.*?\*/)', path.read_text(encoding='utf-8'), re.S)
            if match and ('Copyright' in match[1] or 'copyright' in match[1]):
                blocks.add(match[1])
    target = output / 'commissioner/Everest-NOTICES.txt'
    if blocks:
        data = ('\n\n'.join(sorted(blocks)) + '\n').encode()
        target.write_bytes(data)
    else:
        data = b''
        errors = True
    rows.append({'component': 'Project Everest source and header notices',
                 'version_or_commit': commissioner_provenance['submodules']['third_party/mbedtls/repo'],
                 'license': 'Apache-2.0 (separate from Mbed TLS dual licensing)',
                 'source': 'Mbed TLS 3rdparty/everest leading copyright and license comments',
                 'status': 'collected' if blocks else 'missing Everest notices',
                 'sha256': sha256(data) if blocks else '',
                 'output': target.relative_to(output).as_posix() if blocks else ''})

    # Keep exact original pins, patch and prepared-tree identity beside notices.
    for src, name in [
        (args.commissioner_root / 'tnt-source-provenance.json', 'source-provenance.json'),
        (COMMISSIONER_MANIFEST, 'source-manifest.json'),
        (COMMISSIONER_MANIFEST.parent / commissioner_provenance['patch'], 'source.patch'),
    ]:
        target = output / 'commissioner' / name
        digest = copy_text(src, target)
        rows.append({'component': 'Commissioner modification provenance ' + name,
                     'version_or_commit': commissioner_provenance['revision'],
                     'license': 'BSD-3-Clause; modification retains upstream terms',
                     'source': 'local verified source profile', 'status': 'collected',
                     'sha256': digest, 'output': target.relative_to(output).as_posix()})

    flutter_revision, flutter_provenance = source_revision(args.flutter_root)
    for name, src in [
        ("Flutter framework", args.flutter_root / "packages/flutter/LICENSE"),
        ("Dart SDK", args.flutter_root / "bin/cache/dart-sdk/LICENSE"),
    ]:
        target = output / "flutter" / (safe_name(name) + "-LICENSE.txt")
        if src.is_file():
            digest = copy_text(src, target)
            status = "collected" if not flutter_provenance else f"collected; {flutter_provenance}"
            errors |= bool(flutter_provenance)
        else:
            digest = ""
            status = "missing license text"
            errors = True
        rows.append({"component": name, "version_or_commit": flutter_revision,
                     "license": "Upstream license text included verbatim",
                     "source": f"Flutter SDK relative path: {src.relative_to(args.flutter_root).as_posix()}",
                     "status": status, "sha256": digest,
                     "output": target.relative_to(output).as_posix() if digest else ""})

    config_path = args.app_root / ".dart_tool/package_config.json"
    lock_path = args.app_root / "pubspec.lock"
    if config_path.is_file() and lock_path.is_file():
        config = json.loads(config_path.read_text(encoding="utf-8"))
        roles = read_lock_roles(lock_path)
        packages = {p["name"]: p for p in config["packages"]}
        lock_versions: dict[str, str] = {}
        # Extract version fields by package block. This also avoids a PyYAML dependency.
        current = None
        for line in lock_path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"^  ([^\s][^:]*):\s*$", line)
            if match:
                current = match.group(1)
            elif current and line.startswith("    version:"):
                lock_versions[current] = line.split(":", 1)[1].strip().strip('"')
        for name in sorted(packages):
            if name == "thread_network_tool":
                continue
            package = packages[name]
            root = resolve_root_uri(package["rootUri"], config_path.parent)
            license_file, why = unique_license(root)
            sdk_license = None
            if not license_file:
                sdk_license = flutter_sdk_package_license(root, args.flutter_root)
                if sdk_license:
                    license_file = sdk_license
                    why = "Flutter SDK package license"
            role = roles.get(name, "sdk/transitive")
            target = output / "dart" / (safe_name(name) + ".txt")
            if license_file:
                digest = copy_text(license_file, target)
                status = "collected"
                if sdk_license:
                    rel_source = (
                        f"resolved Flutter SDK package {name}; "
                        "SDK license: packages/flutter/LICENSE"
                    )
                else:
                    rel_source = f"resolved Dart package {name}/{license_file.name}"
            else:
                digest = ""
                status = why
                rel_source = f"resolved Dart package {name}"
                errors = True
            version = lock_versions.get(name)
            if version is None:
                status += "; package version not in lockfile"
                errors = True
            rows.append({"component": f"Dart package {name} ({role})",
                         "version_or_commit": version or "not in lockfile",
                         "license": "See included package license text; not independently classified",
                         "source": rel_source, "status": status,
                         "sha256": digest,
                         "output": target.relative_to(output).as_posix() if digest else ""})
    else:
        rows.append({"component": "Dart resolved package licenses", "version_or_commit": "",
                     "license": "", "source": "app/.dart_tool/package_config.json and app/pubspec.lock",
                     "status": "missing package config or lockfile", "sha256": "", "output": ""})
        errors = True

    notices = args.flutter_notices
    if notices.is_file():
        raw = notices.read_bytes()
        data = gzip.decompress(raw) if notices.name.endswith(".Z") else raw
        target = output / "flutter" / "NOTICES.txt"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        rows.append({"component": "Flutter packaged asset notice bundle", "version_or_commit": "",
                     "license": "Aggregated upstream notices as generated by Flutter build",
                     "source": "macOS app Flutter asset: flutter_assets/NOTICES.Z",
                     "status": "collected from packaged app artifact", "sha256": sha256(data),
                     "output": target.relative_to(output).as_posix()})
    else:
        rows.append({"component": "Flutter packaged asset notice bundle", "version_or_commit": "",
                     "license": "", "source": "expected macOS app flutter_assets/NOTICES.Z",
                     "status": "missing build artifact; Flutter notices not collected", "sha256": "", "output": ""})
        errors = True

    if verify_prepared(args.commissioner_root) != commissioner_provenance:
        raise ValueError('Commissioner source provenance changed during notice collection')
    rows.sort(key=lambda row: (row["component"].casefold(), row["source"].casefold()))
    manifest = [
        "# Collected third-party notice inputs",
        "",
        "Generated from local source trees and build artifacts. This file records provenance; it does not select a project license or resolve legal interpretation.",
        "",
    ]
    for row in rows:
        manifest.extend([
            f"## {row['component']}",
            f"- Version/commit: {row['version_or_commit'] or 'not established'}",
            f"- License: {row['license'] or 'not established'}",
            f"- Source: {row['source']}",
            f"- Status: {row['status']}",
            f"- SHA-256: {row['sha256'] or 'not collected'}",
            f"- Collected file: {row['output'] or 'none'}",
            "",
        ])
    (output / "MANIFEST.md").write_text("\n".join(manifest), encoding="utf-8")
    return [r["status"] for r in rows], errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/release-notices")
    parser.add_argument("--app-root", type=Path, default=ROOT / "app")
    parser.add_argument("--commissioner-root", type=Path, default=configured_commissioner_root())
    parser.add_argument("--flutter-root", type=Path, default=DEFAULT_FLUTTER,
                        help="Flutter SDK root; reported for source auditing, never copied wholesale")
    parser.add_argument("--flutter-notices", type=Path, default=DEFAULT_FLUTTER_NOTICES,
                        help="existing packaged macOS Flutter NOTICES.Z artifact")
    args = parser.parse_args()
    args.output_dir = args.output_dir.resolve()
    args.app_root = args.app_root.resolve()
    args.commissioner_root = args.commissioner_root.resolve()
    args.flutter_root = args.flutter_root.resolve()
    args.flutter_notices = args.flutter_notices.resolve()
    try:
        _, errors = collect(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"notice collection failed: {exc}", file=sys.stderr)
        return 2
    print(f"Notice inputs written to {args.output_dir.relative_to(ROOT) if args.output_dir.is_relative_to(ROOT) else 'requested output directory'}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
