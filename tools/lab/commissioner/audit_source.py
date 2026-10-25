"""Fail closed unless lab source inputs match their reviewed Git objects."""
import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def _git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError("dependency_git_error")
    return result.stdout.strip()


def _require_repo(path):
    path = Path(path).resolve()
    if not path.is_dir():
        raise AssertionError("uninitialized_submodule")
    top = Path(_git(path, "rev-parse", "--show-toplevel")).resolve()
    if top != path:
        raise AssertionError("uninitialized_submodule")
    return path


def _require_clean(repo):
    tracked = _git(
        repo,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "--ignore-submodules=none",
    )
    # Deliberately omit exclude rules: ignored build/cache files are not part of
    # the pinned tree either and may be consumed by configure or build tooling.
    untracked = _git(repo, "ls-files", "--others", "--directory")
    if tracked or untracked:
        raise AssertionError("dirty_dependency")


def audit_dependency(root, expected_head, submodules):
    """Verify one root and its explicitly build-reachable recursive gitlinks."""
    root = _require_repo(root)
    if _git(root, "rev-parse", "HEAD") != expected_head:
        raise AssertionError("dependency_revision")

    repos = {PurePosixPath("."): root}
    for raw_path, expected_revision in sorted(
        submodules.items(), key=lambda item: len(PurePosixPath(item[0]).parts)
    ):
        relative = PurePosixPath(raw_path)
        if relative.is_absolute() or not relative.parts or ".." in relative.parts:
            raise AssertionError("invalid_submodule_path")

        parents = [
            path for path in repos
            if path == PurePosixPath(".") or path == relative.parent or path in relative.parents
        ]
        parent_relative = max(parents, key=lambda path: len(path.parts))
        parent_repo = repos[parent_relative]
        in_parent = relative if parent_relative == PurePosixPath(".") else relative.relative_to(parent_relative)
        tree_entry = _git(parent_repo, "ls-tree", "HEAD", "--", in_parent.as_posix())
        fields = tree_entry.split(None, 3)
        if len(fields) != 4 or fields[0] != "160000" or fields[1] != "commit":
            raise AssertionError("missing_submodule_gitlink")
        if fields[2] != expected_revision:
            raise AssertionError("submodule_gitlink_revision")

        checkout = _require_repo(root.joinpath(*relative.parts))
        if _git(checkout, "rev-parse", "HEAD") != expected_revision:
            raise AssertionError("submodule_checkout_revision")
        repos[relative] = checkout

    for repo in repos.values():
        _require_clean(repo)


def audit_probe_source(path):
    source = Path(path).read_text()
    calls = re.findall(r"commissioner->([A-Za-z0-9_]+)\s*\(", source)
    assert sorted(calls) == sorted(["Init", "Connect", "GetActiveDataset", "GetPendingDataset"])
    assert "Petition(" not in source and "SetPendingDataset(" not in source


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "dependency":
        parser = argparse.ArgumentParser()
        parser.add_argument("mode")
        parser.add_argument("root")
        parser.add_argument("expected_head")
        parser.add_argument("submodule", nargs="*")
        args = parser.parse_args(argv)
        submodules = {}
        for item in args.submodule:
            path, separator, revision = item.partition("=")
            if not separator or not path or not re.fullmatch(r"[0-9a-f]{40}", revision):
                raise AssertionError("invalid_submodule_pin")
            submodules[path] = revision
        audit_dependency(args.root, args.expected_head, submodules)
        return
    if len(argv) != 1:
        raise SystemExit("usage: audit_source.py SOURCE | dependency ROOT HEAD [PATH=HEAD ...]")
    audit_probe_source(argv[0])


if __name__ == "__main__":
    main()
